//
//  OpenProjectSelfHostedForm.swift
//  HelmCode
//
//  Self-hosted Open Project form: runner URL, device name, setup code.
//

import SwiftUI

struct OpenProjectSelfHostedForm: View {
    @Binding var runnerURL: String
    @Binding var deviceName: String
    @Binding var pairingCode: String
    var isConnecting: Bool
    var statusText: String?
    var onConfirm: () -> Void
    /// Present the QR scanner from the parent sheet (avoid nested `.sheet` on iPad).
    var onScanQR: () -> Void = {}

    private var canConfirm: Bool {
        RunnerURL.isValid(runnerURL)
            && !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("http://127.0.0.1:18080", text: $runnerURL)
                    .helmURLFieldStyle()
                    .disabled(isConnecting)
            } header: {
                Text("Runner URL")
            } footer: {
                Text(Copy.runnerFooter)
            }

            Section {
                TextField("iPad", text: $deviceName)
                    .disabled(isConnecting)
            } header: {
                Text("Device name")
            } footer: {
                Text(Copy.nameFooter)
            }

            Section {
                HStack {
                    TextField("SDCN-9XZS", text: $pairingCode)
                        .helmMonospacedFieldStyle()
                        .textInputAutocapitalization(.characters)
                        .disabled(isConnecting)
                        .onChange(of: pairingCode) { _, next in
                            pairingCode = next
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased()
                        }
                    Button(action: onScanQR) {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .disabled(isConnecting)
                    .accessibilityLabel("Scan pairing QR")
                }
            } header: {
                Text("Setup code")
            } footer: {
                Text(Copy.pairFooter)
            }

            if let statusText {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(action: onConfirm) {
                    HStack {
                        Spacer(minLength: 0)
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 8)
                            Text("Connecting…")
                        } else {
                            Text("Add Runner")
                                .fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(!canConfirm || isConnecting)
            }
        }
        .formStyle(.grouped)
    }

    private enum Copy {
        static let runnerFooter =
            "Use the address this iPad can reach. Docker compose publishes host port 18080."
        static let nameFooter =
            "Shown on the runner when another device has to allow this iPad."
        static let pairFooter =
            "From the runner terminal, or from another iPad’s Add device. Looks like SDCN-9XZS."
    }
}
