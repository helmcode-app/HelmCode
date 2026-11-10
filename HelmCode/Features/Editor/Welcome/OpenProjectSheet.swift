//
//  OpenProjectSheet.swift
//  HelmCode
//
//  Add Runner: self-hosted URL + setup code.
//  Pairing does not open a project. The runner page authorizes the repository.
//  Hosted deployment UI is reserved (`OpenProjectHostedPlaceholder`) for later.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OpenProjectSheet: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @Binding var isPresented: Bool

    @State private var runnerURL: String = ""
    @State private var deviceName: String = ""
    @State private var pairingCode: String = ""
    @State private var isConnecting = false
    @State private var statusText: String?
    @State private var errorMessage: String?
    @State private var pairedRunner: EnrolledRunner?
    /// Presented as fullScreenCover — nested `.sheet` inside Add Runner dismisses immediately on iPad.
    @State private var showPairingScanner = false

    var body: some View {
        NavigationStack {
            OpenProjectSelfHostedForm(
                runnerURL: $runnerURL,
                deviceName: $deviceName,
                pairingCode: $pairingCode,
                isConnecting: isConnecting,
                statusText: statusText,
                onConfirm: { Task { await connectSelfHosted() } },
                onScanQR: { showPairingScanner = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .helmInlineNavigationTitle("Add Runner")
            .navigationDestination(item: $pairedRunner) { runner in
                RunnerSetupView(
                    runner: runner,
                    session: session,
                    engine: engine,
                    vfs: vfs,
                    agent: agent,
                    onClose: { isPresented = false },
                    onOpened: { isPresented = false }
                )
            }
            .fullScreenCover(isPresented: $showPairingScanner) {
                PairingQRScannerSheet(
                    onCode: { pairingCode = $0 },
                    onLink: { url in
                        showPairingScanner = false
                        guard let parsed = RunnerPairingLink.parse(url) else { return }
                        runnerURL = parsed.runnerURL
                        pairingCode = parsed.code
                        Task { await connectSelfHosted() }
                    }
                )
            }
            .helmSheetCloseToolbar(disabled: isConnecting) {
                isPresented = false
            }
            .onAppear {
                if runnerURL.isEmpty {
                    runnerURL = RunnerConnectionPrefs.lastURL()
                }
                if deviceName.isEmpty {
                    #if canImport(UIKit)
                    deviceName = UIDevice.current.name
                    #else
                    deviceName = "iPad"
                    #endif
                }
                if let url = RunnerPairingInbox.pending,
                   let parsed = RunnerPairingLink.parse(url) {
                    RunnerPairingInbox.pending = nil
                    runnerURL = parsed.runnerURL
                    pairingCode = parsed.code
                    Task { await connectSelfHosted() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .helmPairingLink)) { note in
                guard let url = note.userInfo?["url"] as? URL,
                      let parsed = RunnerPairingLink.parse(url) else { return }
                runnerURL = parsed.runnerURL
                pairingCode = parsed.code
                Task { await connectSelfHosted() }
            }
            .alert(
                "Couldn’t connect",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Connect

    @MainActor
    private func connectSelfHosted() async {
        isConnecting = true
        defer { isConnecting = false }

        let url = RunnerURL.normalizeHTTP(runnerURL)
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        statusText = nil

        do {
            let client = RunnerCoreAPIClient(baseURLString: url, apiToken: "")
            var enrolled = try await client.enrollDevice(code: code, deviceName: name)
            if enrolled.status == "pending", let enrollmentId = enrolled.enrollmentId {
                statusText = "Waiting for the other device to allow \(name)."
                enrolled = try await pollEnrollment(client: client, id: enrollmentId)
            }
            guard enrolled.status == "complete",
                  let token = enrolled.token,
                  let runnerId = enrolled.runnerId else {
                throw SetupEnrollError.missingToken
            }
            RunnerCredentialStore.save(runnerId: runnerId, token: token)
            session.rememberEnrolledRunner(url: url, runnerId: runnerId, label: name)
            RunnerConnectionPrefs.remember(url: url)
            pairingCode = ""
            statusText = nil
            pairedRunner = EnrolledRunner(
                id: runnerId,
                url: url,
                label: EnrolledRunner.hostLabel(for: url)
            )
        } catch is CancellationError {
            statusText = nil
        } catch {
            statusText = nil
            errorMessage = RunnerAuthCopy.message(for: error)
        }
    }

    private func pollEnrollment(
        client: RunnerCoreAPIClient,
        id: String
    ) async throws -> SetupEnrollResponse {
        for _ in 0..<300 {
            if !isPresented { throw CancellationError() }
            let polled = try await client.pollEnrollment(id: id)
            switch polled.status {
            case "complete":
                return polled
            case "denied":
                throw SetupEnrollError.denied
            case "expired":
                throw SetupEnrollError.expired
            default:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw SetupEnrollError.expired
    }
}
