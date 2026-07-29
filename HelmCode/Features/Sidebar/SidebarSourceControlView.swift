//
//  SidebarSourceControlView.swift
//  HelmCode
//
//  Source Control navigator (local mock until real git is wired).
//

import SwiftUI

struct SidebarSourceControlView: View {
    @ObservedObject var session: WorkspaceSession
    @Binding var commitMessage: String

    var body: some View {
        List {
            if let scm = session.sourceControl {
                branchRow(scm)

                if !scm.staged.isEmpty {
                    ForEach(scm.staged) { change in
                        changeRow(change, staged: true)
                    }
                }

                if scm.unstaged.isEmpty {
                    Text("No unstaged changes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(scm.unstaged) { change in
                        changeRow(change, staged: false)
                    }
                }

                commitBox
                remoteActions

                if let message = scm.lastMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ContentUnavailableView(
                    "No Repository",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Source control becomes available when a project is open.")
                )
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            stageToolbar
        }
    }

    // MARK: - Rows

    private func branchRow(_ scm: SourceControlState) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(scm.branch)
                    .font(.subheadline.weight(.semibold).monospaced())
                if let upstream = scm.upstream {
                    Text(upstream)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Color.accentColor)
        }
    }

    private func changeRow(_ change: GitChange, staged: Bool) -> some View {
        Button {
            if let nodeID = change.nodeID {
                session.openFile(nodeID)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: change.kind.systemImage)
                    .foregroundStyle(change.kind.tintColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(change.fileName)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(change.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(change.kind.shortCode)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(change.kind.tintColor)
            }
        }
        .disabled(change.nodeID == nil)
        .contextMenu {
            if staged {
                Button {
                    session.unstageChange(path: change.path)
                } label: {
                    Label("Unstage", systemImage: "minus.circle")
                }
            } else {
                Button {
                    session.stageChange(path: change.path)
                } label: {
                    Label("Stage", systemImage: "plus.circle")
                }
                if change.kind != .deleted {
                    Button(role: .destructive) {
                        session.discardChange(path: change.path)
                    } label: {
                        Label("Discard", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
    }

    // MARK: - Commit / remote

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .lineLimit(2...4)
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)

            Button {
                session.commitStaged(message: commitMessage)
                if session.lastTreeError == nil,
                   session.sourceControl?.lastMessage?.hasPrefix("Committed") == true {
                    commitMessage = ""
                }
            } label: {
                Label("Commit", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, 4)
    }

    private var remoteActions: some View {
        HStack(spacing: 12) {
            Button {
                session.pull()
            } label: {
                Label("Pull", systemImage: "arrow.down")
            }
            Button {
                session.push()
            } label: {
                Label("Push", systemImage: "arrow.up")
            }
            Button {
                session.fetch()
            } label: {
                Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var stageToolbar: some View {
        if let scm = session.sourceControl, scm.changeCount > 0 {
            HStack(spacing: 12) {
                if !scm.unstaged.isEmpty {
                    Button {
                        session.stageAll()
                    } label: {
                        Label("Stage All", systemImage: "plus.circle")
                    }
                }
                if !scm.staged.isEmpty {
                    Button {
                        session.unstageAll()
                    } label: {
                        Label("Unstage All", systemImage: "minus.circle")
                    }
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

extension GitChangeKind {
    var tintColor: Color {
        switch self {
        case .added, .untracked: return .green
        case .modified: return .orange
        case .deleted: return .red
        }
    }
}
