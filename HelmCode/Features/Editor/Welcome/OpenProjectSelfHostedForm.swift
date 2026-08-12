//
//  OpenProjectSelfHostedForm.swift
//  HelmCode
//
//  Self-hosted Open Project form: runner URL, optional token, confirm.
//

import SwiftUI

struct OpenProjectSelfHostedForm: View {
    @Binding var runnerURL: String
    @Binding var apiToken: String
    var isConnecting: Bool
    var onConfirm: () -> Void

    private var canConfirm: Bool {
        RunnerURL.isValid(runnerURL)
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
                SecureField("Bearer token (optional)", text: $apiToken)
                    .helmMonospacedFieldStyle()
                    .disabled(isConnecting)
                    .textContentType(.password)
            } header: {
                Text("API Token")
            } footer: {
                Text(Copy.tokenFooter)
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
                            Text("Confirm")
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
            "Docker compose publishes host port 18080 → container 8080. Same host serves HTTP, VFS (/v1/vfs), and Agent sessions (/v1/sessions)."
        static let tokenFooter =
            "Required only when the runner sets OPENCORE_API_TOKEN. Leave empty for unauthenticated local dev."
    }
}
