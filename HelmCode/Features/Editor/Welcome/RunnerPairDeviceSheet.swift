//
//  RunnerPairDeviceSheet.swift
//  HelmCode
//
//  Authorize another device via QR code or 8-character setup code.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CoreImage.CIFilterBuiltins

struct RunnerPairDeviceSheet: View {
    let runner: EnrolledRunner
    @ObservedObject var session: WorkspaceSession
    var onClose: () -> Void

    @State private var ticket: SetupPairTicket?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingEnrollments: [SetupPendingEnrollment] = []
    @State private var busyEnrollmentId: String?
    @State private var approvedDeviceName: String?
    @State private var copiedCode = false

    private var client: RunnerCoreAPIClient? {
        let runnerId = session.enrolledRunners.first(where: {
            $0.id == runner.id || $0.url == RunnerURL.normalizeHTTP(runner.url)
        })?.id ?? runner.id
        let token = RunnerCredentialStore.token(runnerId: runnerId) ?? ""
        guard !token.isEmpty else { return nil }
        return RunnerCoreAPIClient(baseURLString: runner.url, apiToken: token)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading && ticket == nil {
                        loadingView
                    } else if let error = errorMessage, ticket == nil {
                        errorView(error)
                    } else if let ticket {
                        pairingContent(ticket)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .helmInlineNavigationTitle("Pair Another Device")
            .helmSheetCloseToolbar(action: onClose)
            .task {
                await loadTicket()
            }
            .task {
                await pollPendingEnrollments()
            }
        }
    }

    // MARK: - Loading & Error States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Generating pairing code…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 60)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Couldn’t Generate Pairing Code")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await loadTicket() }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Main Content

    @ViewBuilder
    private func pairingContent(_ ticket: SetupPairTicket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scan to Connect")
                .font(.headline)
            Text("Open **Add Runner** on another iPad and tap the QR scanner icon, or manually enter the 8-character code below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        qrCard(ticket)

        codeCard(ticket.code)

        if let name = approvedDeviceName {
            approvedBanner(name)
        }

        if !pendingEnrollments.isEmpty {
            pendingApprovalsCard
        }
    }

    // MARK: - QR Code Card

    private func qrCard(_ ticket: SetupPairTicket) -> some View {
        VStack(spacing: 12) {
            if let image = makeQRImage(from: ticket) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                #endif
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
            }

            Text("Pairing with \(runner.displayLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Code Card

    private func codeCard(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETUP CODE")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(code)
                    .font(.title2.monospaced().weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Button {
                    copyCode(code)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                            .font(.body.weight(.semibold))
                        Text(copiedCode ? "Copied" : "Copy")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(width: 64, height: 56)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    // MARK: - Pending Approvals Card

    private var pendingApprovalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Connection Request")
                    .font(.headline)
            }

            Text("A device scanned this QR code and is requesting permission to connect to this runner.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(pendingEnrollments) { enrollment in
                HStack(spacing: 12) {
                    Image(systemName: "ipad")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(enrollment.deviceName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Requested access")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if busyEnrollmentId == enrollment.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        HStack(spacing: 8) {
                            Button("Deny", role: .destructive) {
                                Task { await decide(enrollment, approve: false) }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)

                            Button("Allow") {
                                Task { await decide(enrollment, approve: true) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func approvedBanner(_ deviceName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body.weight(.semibold))

            Text("**\(deviceName)** authorized successfully! That device will finish pairing automatically.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            Color.green.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Actions

    @MainActor
    private func loadTicket() async {
        guard let client else {
            errorMessage = "Runner client credential not found."
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            ticket = try await client.startDeviceInvite(url: runner.url)
            isLoading = false
        } catch {
            errorMessage = RunnerAuthCopy.message(for: error)
            isLoading = false
        }
    }

    @MainActor
    private func pollPendingEnrollments() async {
        while !Task.isCancelled {
            if let client, let list = try? await client.listPendingEnrollments() {
                self.pendingEnrollments = list.enrollments
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    @MainActor
    private func decide(_ enrollment: SetupPendingEnrollment, approve: Bool) async {
        guard let client else { return }
        busyEnrollmentId = enrollment.id
        defer { busyEnrollmentId = nil }
        do {
            if approve {
                try await client.approveEnrollment(id: enrollment.id)
                withAnimation {
                    approvedDeviceName = enrollment.deviceName
                    pendingEnrollments.removeAll { $0.id == enrollment.id }
                }
            } else {
                try await client.denyEnrollment(id: enrollment.id)
                withAnimation {
                    pendingEnrollments.removeAll { $0.id == enrollment.id }
                }
            }
        } catch {
            errorMessage = RunnerAuthCopy.message(for: error)
        }
    }

    private func copyCode(_ code: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #endif
        copiedCode = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedCode = false
        }
    }

    #if canImport(UIKit)
    private func makeQRImage(from ticket: SetupPairTicket) -> UIImage? {
        if let dataUrl = ticket.qrDataUrl,
           let img = imageFromDataUrl(dataUrl) {
            return img
        }
        if let payload = ticket.qrPayload {
            return generateQRCode(from: payload)
        }
        return nil
    }

    private func imageFromDataUrl(_ dataUrl: String) -> UIImage? {
        let prefix = "data:image/png;base64,"
        guard dataUrl.hasPrefix(prefix),
              let data = Data(base64Encoded: String(dataUrl.dropFirst(prefix.count))) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    #endif
}
