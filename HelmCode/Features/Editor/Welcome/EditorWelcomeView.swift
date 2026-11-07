//
//  EditorWelcomeView.swift
//  HelmCode
//
//  Center-column start page when no project is open: header, quick actions,
//  paired runners, and recent workspaces.
//

import SwiftUI

struct EditorWelcomeView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    var onOpenSettings: (() -> Void)?

    @State private var isOpenProjectPresented = false
    @State private var isBrowseProjectsPresented = false
    @State private var projectSettingsID: WorkspaceProject.ID?
    @State private var runnerPage: EnrolledRunner?

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
            VStack(alignment: .leading, spacing: 32) {
                header
                quickActionsSection
                runnersSection
                recentSection
            }
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 44)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $isOpenProjectPresented) {
            OpenProjectSheet(
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                isPresented: $isOpenProjectPresented
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmPairingLink)) { _ in
            isOpenProjectPresented = true
        }
        .onAppear {
            if RunnerPairingInbox.pending != nil {
                isOpenProjectPresented = true
            }
        }
        .sheet(item: $runnerPage) { runner in
            RunnerSetupSheet(
                runner: runner,
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                onClose: { runnerPage = nil }
            )
        }
        .sheet(isPresented: $isBrowseProjectsPresented) {
            BrowseProjectsSheet(
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                runnerStatus: runnerStatus,
                isPresented: $isBrowseProjectsPresented
            )
        }
        .projectSettingsSheet(
            projectID: $projectSettingsID,
            session: session,
            engine: engine,
            vfs: vfs,
            agent: agent
        )
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

            Spacer(minLength: 0)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCaption(title: "Start")

            HStack(spacing: 14) {
                commandTile(
                    title: "Add Runner…",
                    subtitle: "Pair with a self-hosted runner via 8-char code or QR",
                    systemImage: "server.rack",
                    tint: .green
                ) {
                    isOpenProjectPresented = true
                }

                commandTile(
                    title: "Settings",
                    subtitle: "Appearance, editor keybindings & AI model preferences",
                    systemImage: "slider.horizontal.3",
                    tint: .orange
                ) {
                    onOpenSettings?()
                }
            }
        }
    }

    private func commandTile(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paired Runners

    @ViewBuilder
    private var runnersSection: some View {
        if !session.enrolledRunners.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionCaption(title: "Paired Runners")
                    Spacer()
                    Text("\(session.enrolledRunners.count) enrolled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                InsetGroupedCard {
                    ForEach(Array(session.enrolledRunners.enumerated()), id: \.element.id) { index, runner in
                        if index > 0 { InsetGroupedRowDivider(leadingInset: 54) }
                        runnerRackRow(runner)
                    }
                }
            }
        }
    }

    private func runnerRackRow(_ runner: EnrolledRunner) -> some View {
        let count = workspaceCount(for: runner)
        return Button {
            runnerPage = runner
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(runner.displayLabel)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(count == 1 ? "1 repo" : "\(count) repos")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Color.secondary.opacity(0.14),
                                in: Capsule(style: .continuous)
                            )
                    }

                    Text(runner.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text("Manage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func workspaceCount(for runner: EnrolledRunner) -> Int {
        let normalized = RunnerURL.normalizeHTTP(runner.url)
        return session.projects.filter {
            $0.runnerId == runner.id || ($0.runnerId == nil && $0.normalizedRunnerURL == normalized)
        }.count
    }

    // MARK: - Recent Workspaces

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionCaption(title: "Recent Workspaces")
                Spacer()
                if !session.recentProjects.isEmpty {
                    Text("\(session.recentProjects.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if recentVisible.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No recent workspaces yet")
                            .font(.subheadline.weight(.medium))
                        Text("Pair a runner above, then clone or open a GitHub repository.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            } else {
                InsetGroupedCard {
                    ForEach(Array(recentVisible.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { InsetGroupedRowDivider() }
                        recentProjectRow(project)
                    }

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
                subtitle: "Browse all \(session.projects.count) workspaces",
                systemImage: "ellipsis.circle"
            )
        }
        .buttonStyle(.plain)
    }

    private func recentProjectRow(_ project: WorkspaceProject) -> some View {
        Button {
            session.openProject(project.id)
        } label: {
            IconListRow(
                project: project,
                runnerStatus: runnerStatus.displayStatus(
                    for: project,
                    engine: engine,
                    vfs: vfs
                )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            ProjectListContextMenu(
                project: project,
                onProjectSettings: { projectSettingsID = project.id },
                onRemoveFromRecents: { session.removeFromRecents(project.id) },
                onRemoveProject: { session.removeProject(project.id) }
            )
        }
    }
}

#Preview {
    EditorWelcomeView(
        session: WorkspaceSession(),
        engine: HelmCodeNetworkEngine(),
        vfs: VFSNetworkEngine(),
        agent: AgentNetworkEngine(),
        runnerStatus: ProjectRunnerStatusMonitor()
    )
}
