//
//  EditorWelcomeView.swift
//  HelmCode
//
//  Center-column start page when no project is open (VS Code / Xcode style).
//

import SwiftUI

struct EditorWelcomeView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    var onOpenSettings: (() -> Void)?

    @State private var isOpenProjectPresented = false
    @State private var isBrowseProjectsPresented = false

    private enum Metrics {
        /// Recent list on the welcome page (More opens the full browser).
        static let recentVisibleLimit = 5
    }

    private var recentVisible: [WorkspaceProject] {
        Array(session.recentProjects.prefix(Metrics.recentVisibleLimit))
    }

    private var hasMoreRecents: Bool {
        session.recentProjects.count > Metrics.recentVisibleLimit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                startSection
                recentSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $isOpenProjectPresented) {
            OpenProjectSheet(
                session: session,
                engine: engine,
                vfs: vfs,
                isPresented: $isOpenProjectPresented
            )
        }
        .sheet(isPresented: $isBrowseProjectsPresented) {
            BrowseProjectsSheet(
                session: session,
                engine: engine,
                vfs: vfs,
                runnerStatus: runnerStatus,
                isPresented: $isBrowseProjectsPresented
            )
        }
        .task {
            runnerStatus.refresh(projects: session.projects, engine: engine)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("HelmCode")
                    .font(.largeTitle.weight(.semibold))
                Text("AI coding console for iPad")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Start

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(title: "Start")

            InsetGroupedCard {
                startRow(
                    title: "Open Project…",
                    systemImage: "folder.badge.plus",
                    detail: "Hosted or self-hosted runner"
                ) {
                    isOpenProjectPresented = true
                }

                InsetGroupedRowDivider()

                startRow(
                    title: "Clone Repository…",
                    systemImage: "arrow.down.doc",
                    detail: "Coming soon",
                    isEnabled: false
                ) {}

                InsetGroupedRowDivider()

                startRow(
                    title: "Settings",
                    systemImage: "gearshape",
                    detail: "Appearance, layout, backend"
                ) {
                    onOpenSettings?()
                }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(title: "Recent")

            if recentVisible.isEmpty {
                Text("No recent projects yet. Open a project to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                InsetGroupedCard {
                    ForEach(Array(recentVisible.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { InsetGroupedRowDivider() }
                        recentProjectRow(project)
                    }

                    // Full catalog browser (previous Open Project list).
                    if hasMoreRecents {
                        InsetGroupedRowDivider()
                        moreRow
                    }
                }
            }
        }
    }

    private var moreRow: some View {
        Button {
            isBrowseProjectsPresented = true
        } label: {
            IconListRow(
                title: "More…",
                subtitle: "Browse all projects",
                systemImage: "ellipsis.circle"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private func startRow(
        title: String,
        systemImage: String,
        detail: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            IconListRow(
                title: title,
                subtitle: detail,
                systemImage: systemImage,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func recentProjectRow(_ project: WorkspaceProject) -> some View {
        Button {
            session.openProject(project.id)
        } label: {
            IconListRow(
                title: project.name,
                subtitle: project.branchRemoteLine,
                subtitleMonospaced: true,
                systemImage: "folder.fill",
                runnerStatus: runnerStatus.displayStatus(
                    for: project,
                    engine: engine,
                    vfs: vfs
                )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                session.removeFromRecents(project.id)
            } label: {
                Label("Remove from Recents", systemImage: "trash")
            }
            Button(role: .destructive) {
                session.removeProject(project.id)
            } label: {
                Label("Remove Project", systemImage: "folder.badge.minus")
            }
        }
    }
}

#Preview {
    EditorWelcomeView(
        session: WorkspaceSession(),
        engine: HelmCodeNetworkEngine(),
        vfs: VFSNetworkEngine(),
        runnerStatus: ProjectRunnerStatusMonitor()
    )
}
