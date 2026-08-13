//
//  SidebarSourceControlView.swift
//  HelmCode
//
//  Features/SourceControl — sidebar navigator:
//  Changes → Local Branches → Remote Branches → Tags.
//  Diff / checkout via context menus.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SidebarSourceControlView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var vfs: VFSNetworkEngine

    @State private var showLocalBranches = true
    @State private var showRemoteBranches = false
    @State private var showTags = false

    var body: some View {
        List {
            if let scm = session.sourceControl {
                changesSection(scm)
                refsSection(
                    title: "Local Branches",
                    count: scm.localBranches.count,
                    isExpanded: $showLocalBranches,
                    refs: scm.localBranches
                )
                refsSection(
                    title: "Remote Branches",
                    count: scm.remoteBranches.count,
                    isExpanded: $showRemoteBranches,
                    refs: scm.remoteBranches
                )
                refsSection(
                    title: "Tags",
                    count: scm.tags.count,
                    isExpanded: $showTags,
                    refs: scm.tags
                )
                footerHint
            } else {
                ContentUnavailableView(
                    "No Repository",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Source control becomes available when a project is open.")
                )
            }
        }
        .helmSidebarListStyle()
        .refreshable {
            await WorkspaceRuntimeBridge.refreshSourceControl(
                from: vfs,
                to: session,
                forceLoading: true
            )
        }
    }

    // MARK: - Changes

    @ViewBuilder
    private func changesSection(_ scm: SourceControlState) -> some View {
        // Hide the whole section when clean; keep loading / error / unavailable visible.
        if scm.phase == .ready && scm.changeCount == 0 {
            EmptyView()
        } else {
            Section {
                switch scm.phase {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking status…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("Not a Git repository")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .error:
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scm.errorMessage ?? "Could not load status")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") {
                            Task {
                                await WorkspaceRuntimeBridge.refreshSourceControl(
                                    from: vfs,
                                    to: session,
                                    forceLoading: true
                                )
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                case .ready:
                    ForEach(scm.sortedChanges) { change in
                        changeRow(change)
                    }
                }
            } header: {
                Text("Changes\(scm.changeCount > 0 ? " (\(scm.changeCount))" : "")")
            }
        }
    }

    private func changeRow(_ change: GitChange) -> some View {
        Button {
            if let nodeID = change.nodeID {
                session.openFile(nodeID)
            }
        } label: {
            HStack(spacing: 8) {
                FileTypeIcon(
                    languageHint: FileLanguageHint.resolve(fileName: change.fileName),
                    size: FileTypeIconMetrics.compact
                )
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(change.nodeID == nil && change.kind == .deleted)
        .contextMenu {
            Button {
                session.openSourceControlDiff(change)
            } label: {
                Label("Diff", systemImage: "doc.badge.ellipsis")
            }
            if let nodeID = change.nodeID {
                Button {
                    session.openFile(nodeID)
                } label: {
                    Label("Open File", systemImage: "doc")
                }
            }
            Button {
                copyPath(change.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Refs

    private func refsSection(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        refs: [GitRef]
    ) -> some View {
        Section(isExpanded: isExpanded) {
            if refs.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(refs) { ref in
                    refRow(ref)
                }
            }
        } header: {
            Text("\(title) (\(count))")
        }
    }

    private func refRow(_ ref: GitRef) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ref.systemImage)
                .foregroundStyle(ref.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(ref.name)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(ref.isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if ref.isCurrent {
                        Text("HEAD")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                    }
                }
                if let tip = ref.tip {
                    Text(tip)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel(ref.isCurrent ? "\(ref.name), current HEAD" : ref.name)
        .contextMenu {
            refContextMenu(ref)
        }
    }

    @ViewBuilder
    private func refContextMenu(_ ref: GitRef) -> some View {
        if !ref.isCurrent {
            Button {
                Task {
                    await WorkspaceRuntimeBridge.checkoutSourceControlRef(
                        ref,
                        from: vfs,
                        to: session
                    )
                }
            } label: {
                switch ref.kind {
                case .localBranch:
                    Label("Switch to Branch", systemImage: "arrow.triangle.swap")
                case .remoteBranch:
                    Label("Checkout Branch", systemImage: "arrow.down.circle")
                case .tag:
                    Label("Checkout Tag", systemImage: "tag")
                }
            }
        }
        Button {
            copyPath(ref.name)
        } label: {
            Label("Copy Name", systemImage: "doc.on.doc")
        }
    }

    private var footerHint: some View {
        Section {
            Text("Commit and sync from Terminal or Agent")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private func copyPath(_ path: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = path
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #endif
    }

}

extension GitChangeKind {
    var tintColor: Color {
        switch self {
        case .added, .untracked: return .green
        case .modified, .renamed: return .orange
        case .deleted: return .red
        }
    }
}
