//
//  CommanderView.swift
//  HelmCode
//
//  AI agent command terminal — timeline + composer.
//  Title + collapse control live in the system toolbar trailing group (DetailCanvasView).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CommanderView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine

    @State private var prompt: String = ""
    @State private var isSubmitting = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            timeline
            Divider()
            composer
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if engine.events.isEmpty {
                        emptyTimeline
                    } else {
                        ForEach(engine.events) { event in
                            CommanderEventRow(event: event)
                                .id(event.id)
                        }
                    }

                    if let result = engine.result {
                        CommanderResultBanner(result: result)
                            .id("result-banner")
                            .padding(.top, 8)
                    }

                    if let err = engine.lastError, engine.result == nil {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(12)
                            .id("error-banner")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: engine.events.count) { _, _ in
                if let last = engine.events.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: engine.result?.taskId) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("result-banner", anchor: .bottom)
                }
            }
        }
    }

    private var emptyTimeline: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Event timeline")
                .font(.headline)
            Text("Submit a task to stream runner-core progress events into this console.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Task prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                phaseChip
                Spacer(minLength: 0)
                Text("\(prompt.count)/\(engine.promptCharacterLimit)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(prompt.count > engine.promptCharacterLimit ? .red : .secondary)
                if engine.phase.isBusy {
                    Button("Cancel", role: .destructive) {
                        Task { await engine.cancelActiveTask() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                }
                Button {
                    engine.resetSession()
                    prompt = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(engine.phase.isBusy)
                .accessibilityLabel("Clear session")
            }

            TextField(
                "Describe the coding task for the agent…",
                text: $prompt,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...8)
            .focused($promptFocused)
            .padding(10)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .disabled(engine.phase.isBusy)

            HStack {
                if !engine.connectionState.isOnline {
                    Label("Backend offline", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting || engine.phase.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Label("Run Task", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }

    private var phaseChip: some View {
        Text(engine.phase.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.15), in: Capsule())
            .foregroundStyle(phaseColor)
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .idle: return .secondary
        case .submitting, .running: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !engine.phase.isBusy
            && !isSubmitting
            && prompt.count <= engine.promptCharacterLimit
            && engine.connectionState.isOnline
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await engine.submitAsyncTask(prompt: prompt)
            prompt = ""
            promptFocused = false
        } catch {
            // engine.lastError / phase already updated
        }
    }
}
