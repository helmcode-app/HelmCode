//
//  CommanderView.swift
//  HelmCode
//
//  AI agent command terminal — timeline + Cursor-style composer.
//  Hosted in the system `.inspector` column (see RootView).
//  Toggle lives on EditorDetailView’s system toolbar.
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
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Hardware-keyboard focus can shift the column up and expose the
        // inspector chrome below; paint the same fill into that gap.
        .background {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
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

    // MARK: - Composer (Cursor-style input card)

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "Describe the coding task for the agent…",
                text: $prompt,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...8)
            .focused($promptFocused)
            .disabled(engine.phase.isBusy)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Footer inside the input card: status (leading) + send (trailing).
            HStack(spacing: 8) {
                backendStatusLabel
                phaseChip
                Spacer(minLength: 0)

                if engine.phase.isBusy {
                    Button {
                        Task { await engine.cancelActiveTask() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel task")
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting || engine.phase.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        // System circular glyph (not a custom bordered button style).
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                canSubmit ? Color.white : Color.secondary,
                                canSubmit ? Color.accentColor : Color.secondary.opacity(0.25)
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Run task")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(12)
    }

    private var backendStatusLabel: some View {
        HStack(spacing: 6) {
            ConnectionStatusDot(state: engine.connectionState)
            Text(engine.connectionState.shortTitle)
                .font(.caption)
                .foregroundStyle(engine.connectionState.isOnline ? Color.secondary : Color.red)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
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
