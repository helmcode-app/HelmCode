//
//  AgentSessionPicker.swift
//  HelmCode
//
//  Cursor-style chat history list: search, new chat, switch, delete.
//

import SwiftUI

struct AgentSessionPickerSheet: View {
    @ObservedObject var agent: AgentNetworkEngine
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var pendingDelete: AgentSessionDTO?

    private var filtered: [AgentSessionDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return agent.sessions }
        return agent.sessions.filter { item in
            let title = item.title ?? ""
            return title.localizedCaseInsensitiveContains(q)
                || item.id.localizedCaseInsensitiveContains(q)
                || item.status.rawValue.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            await agent.startNewChat()
                            dismiss()
                        }
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.phase.isBusy)
                }

                Section {
                    if agent.sessions.isEmpty {
                        ContentUnavailableView(
                            "No chats yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Start a new chat to talk with the agent.")
                        )
                        .listRowBackground(Color.clear)
                    } else if filtered.isEmpty {
                        Text("No matches for “\(query)”")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { item in
                            sessionRow(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        pendingDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(agent.phase.isBusy)
                                }
                                .contextMenu {
                                    Button {
                                        Task {
                                            await agent.selectSession(id: item.id)
                                            dismiss()
                                        }
                                    } label: {
                                        Label("Open", systemImage: "arrow.right.circle")
                                    }
                                    .disabled(agent.phase.isBusy)

                                    Button(role: .destructive) {
                                        pendingDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(agent.phase.isBusy)
                                }
                        }
                    }
                } header: {
                    Text(filtered.isEmpty && !query.isEmpty ? "Results" : "History")
                }
            }
            .listStyle(.insetGrouped)
            .helmInlineNavigationTitle("Chats")
            .searchable(text: $query, prompt: "Search chats")
            .helmSheetCloseToolbar {
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await agent.refreshSessionList() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .task {
                await agent.refreshSessionList()
            }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { item in
                Button("Delete chat", role: .destructive) {
                    Task {
                        await agent.deleteSession(id: item.id)
                        pendingDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { item in
                Text(item.title?.isEmpty == false ? item.title! : "Untitled chat")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Row

    @ViewBuilder
    private func sessionRow(_ item: AgentSessionDTO) -> some View {
        Button {
            Task {
                await agent.selectSession(id: item.id)
                dismiss()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.id == agent.activeSessionID
                      ? "bubble.left.and.bubble.right.fill"
                      : "bubble.left.and.bubble.right")
                    .font(.body)
                    .foregroundStyle(item.id == agent.activeSessionID ? Color.accentColor : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle(for: item))
                        .font(.subheadline.weight(item.id == agent.activeSessionID ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        statusDot(for: item.status)
                        Text(relativeTime(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SelectableListCheckmark(selected: item.id == agent.activeSessionID)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(agent.phase.isBusy)
    }

    private func displayTitle(for item: AgentSessionDTO) -> String {
        if let t = item.title, !t.isEmpty { return t }
        return "Untitled chat"
    }

    private func statusDot(for status: SessionStatusWire) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 6, height: 6)
            .accessibilityLabel(status.rawValue)
    }

    private func statusColor(_ status: SessionStatusWire) -> Color {
        switch status {
        case .running: return .accentColor
        case .completed, .idle: return .secondary.opacity(0.55)
        case .failed: return .red
        case .cancelled: return .orange
        case .unknown: return .secondary.opacity(0.35)
        }
    }

    private func relativeTime(for item: AgentSessionDTO) -> String {
        guard let date = Date.helmParseWire(item.updatedAt ?? item.createdAt) else {
            return item.status.rawValue
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
