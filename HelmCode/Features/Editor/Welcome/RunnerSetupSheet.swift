//
//  RunnerSetupSheet.swift
//  HelmCode
//
//  Runner management: status header, mounted workspaces, ACP harness selection,
//  GitHub Device Flow, and searchable repo catalog.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RunnerSetupSheet: View {
    let runner: EnrolledRunner
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            RunnerSetupView(
                runner: runner,
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                onClose: onClose,
                onOpened: onClose
            )
        }
    }
}

struct RunnerSetupView: View {
    let runner: EnrolledRunner
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    var onClose: () -> Void
    var onOpened: () -> Void

    @State private var status: SetupSessionStatus?
    @State private var repos: [GithubRepoRecord] = []
    @State private var repoFilter: String = ""
    @State private var github: GithubDeviceStart?
    @State private var pollToken = 0
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var isAddingRepo = false
    @State private var reAuthCode = ""
    @State private var isReAuthBusy = false
    @State private var statusText: String?
    @State private var copiedDeviceCode = false
    /// Inline: device unauthorized recovery.
    @State private var errorMessage: String?
    /// Floating top toast banner for clone / GitHub / open failures.
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var isPairDevicePresented = false

    /// Anchor ID for scrolling to the GitHub provisioning / device authorization card.
    private let githubSectionID = "github-provisioning-section"

    private var runnerProjects: [WorkspaceProject] {
        session.projects.filter {
            $0.runnerId == runner.id ||
            ($0.runnerId == nil && $0.normalizedRunnerURL == RunnerURL.normalizeHTTP(runner.url))
        }
    }

    private var clonedRepoKeys: Set<String> {
        var keys = Set<String>()
        for workspace in status?.workspaces ?? [] {
            if let repo = workspace.repo {
                keys.insert(Self.repoKey(owner: repo.owner, repo: repo.repo))
            }
        }
        if let repo = status?.repo {
            keys.insert(Self.repoKey(owner: repo.owner, repo: repo.repo))
        }
        return keys
    }

    private var hasGithubLink: Bool {
        let login = status?.githubLogin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !login.isEmpty
    }

    private var filteredRepos: [GithubRepoRecord] {
        let query = repoFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return repos }
        return repos.filter { $0.slug.lowercased().contains(query) }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 24) {
                    rackTelemetryCard(proxy: proxy)

                    if let statusText {
                        liveOperationBanner(statusText)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isUnauthorized {
                        unauthorizedRecoveryCard
                    } else {
                        mountedWorkspacesSection
                        githubProvisioningSection
                            .id(githubSectionID)
                    }

                    dangerZoneSection

                    if !isUnauthorized {
                        RunnerAgentConfigSection(
                            makeClient: { client() },
                            isParentBusy: isBusy,
                            onToast: { presentError($0) },
                            onAgentBecameReady: {
                                let sameRunner =
                                    RunnerURL.normalizeHTTP(agent.baseURLString)
                                    == RunnerURL.normalizeHTTP(runner.url)
                                if sameRunner {
                                    agent.reconnectNow(reason: "agent harness ready")
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            if let toastMessage {
                floatingErrorToast(message: toastMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: toastMessage)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: statusText)
        .helmInlineNavigationTitle(runner.displayLabel)
        .helmSheetCloseToolbar(disabled: isBusy, action: onClose)
        .task { await reload() }
        .task(id: pollToken) { await pollGithubIfNeeded() }
        .refreshable { await reload() }
        .sheet(isPresented: $isPairDevicePresented) {
            RunnerPairDeviceSheet(
                runner: runner,
                session: session,
                onClose: { isPairDevicePresented = false }
            )
        }
    }

    // MARK: - Telemetry Header Card

    private func rackTelemetryCard(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "server.rack")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(runner.displayLabel)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        telemetryPill
                    }

                    Text(runner.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 16) {
                telemetryMetric(
                    label: "Workspaces",
                    value: "\(repositoryEntries.count)",
                    icon: "square.stack.3d.up.fill"
                )

                Divider()
                    .frame(height: 28)

                telemetryMetric(
                    label: "GitHub",
                    value: hasGithubLink ? "@\(status?.githubLogin ?? "")" : "Not linked",
                    icon: "person.badge.key.fill",
                    accent: hasGithubLink ? .primary : .secondary
                )

                Spacer(minLength: 0)

                if hasGithubLink && !isUnauthorized {
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            proxy.scrollTo(githubSectionID, anchor: .top)
                        }
                        Task {
                            await reconnectGithub()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                proxy.scrollTo(githubSectionID, anchor: .top)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Re-auth GitHub")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color(.tertiarySystemFill),
                            in: Capsule(style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || isLoading)
                }
            }
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var telemetryPill: some View {
        let (title, color): (String, Color) = {
            if isLoading && status == nil {
                return ("Connecting", .orange)
            }
            if isUnauthorized {
                return ("Auth required", .orange)
            }
            if status != nil {
                return ("Online", .green)
            }
            return ("Offline", .red)
        }()

        return Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func telemetryMetric(
        label: String,
        value: String,
        icon: String,
        accent: Color = .primary
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Banners & Toasts

    private func liveOperationBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func floatingErrorToast(message: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn’t complete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                toastDismissTask?.cancel()
                toastMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .helmSystemGlassPanel(cornerRadius: 14, interactive: false)
    }

    // MARK: - Unauthorized Recovery

    private var isUnauthorized: Bool {
        errorMessage == RunnerAuthCopy.unauthorized ||
        (errorMessage?.contains("not authorized") == true)
    }

    private var unauthorizedRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Device Token Revoked or Reset")
                    .font(.headline)
            }

            Text("This iPad’s credential is no longer accepted by the runner. Enter a fresh 8-character setup code to re-authorize in place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("SDCN-9XZS", text: $reAuthCode)
                    .helmMonospacedFieldStyle()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .disabled(isReAuthBusy)
                    .onChange(of: reAuthCode) { _, next in
                        reAuthCode = next.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    }

                Button {
                    Task { await submitReAuth() }
                } label: {
                    HStack(spacing: 6) {
                        if isReAuthBusy {
                            ProgressView().controlSize(.small)
                        }
                        Text("Re-authorize")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        reAuthCode.isEmpty || isReAuthBusy
                            ? Color.accentColor.opacity(0.35)
                            : Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(reAuthCode.isEmpty || isReAuthBusy)
            }

            Text("Run `node dist/entrypoint.js setup:enroll` on the runner or generate a code from another paired iPad.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Mounted Workspaces

    private var remoteWorkspaces: [SetupWorkspaceRef] {
        let rows = status?.workspaces ?? []
        let extras = rows.filter { $0.kind != "primary" }
        let primary = rows.filter {
            $0.kind == "primary" && ($0.repo != nil || (extras.isEmpty && status?.hasRepo == true))
        }
        return primary + extras
    }

    private struct MountedRepoEntry: Identifiable {
        let id: String
        let title: String
        let branch: String?
        let subtitle: String
        let workspaceId: String
        let isPrimary: Bool
    }

    private var repositoryEntries: [MountedRepoEntry] {
        var rows: [MountedRepoEntry] = []
        var seen = Set<String>()
        for project in runnerProjects {
            let wid = project.workspaceId
            seen.insert(wid)
            let branch = project.trimmedBranch.isEmpty ? nil : project.trimmedBranch
            rows.append(
                MountedRepoEntry(
                    id: project.id,
                    title: project.displayName,
                    branch: branch,
                    subtitle: project.remote,
                    workspaceId: wid,
                    isPrimary: wid == "default"
                )
            )
        }
        for workspace in remoteWorkspaces where !seen.contains(workspace.id) {
            seen.insert(workspace.id)
            rows.append(
                MountedRepoEntry(
                    id: workspace.id,
                    title: workspace.displayName,
                    branch: nil,
                    subtitle: workspace.path,
                    workspaceId: workspace.id,
                    isPrimary: workspace.kind == "primary"
                )
            )
        }
        return rows
    }

    private var mountedWorkspacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(title: "Mounted Workspaces")
                Spacer()
                if !repositoryEntries.isEmpty {
                    Text("\(repositoryEntries.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if repositoryEntries.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isLoading ? "Scanning runner workspaces…" : "No repositories mounted yet")
                            .font(.subheadline.weight(.medium))
                        Text("Clone a GitHub repository below to initialize a workspace on this runner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(repositoryEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 56)
                        }
                        mountedWorkspaceRow(entry)
                    }
                }
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    private func mountedWorkspaceRow(_ entry: MountedRepoEntry) -> some View {
        Button {
            Task { await openProject(workspaceId: entry.workspaceId) }
        } label: {
            HStack(spacing: 12) {
                ProjectAvatarIcon(name: entry.title, seed: entry.workspaceId, size: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let branch = entry.branch {
                            Text(branch)
                                .font(.caption2.weight(.semibold).monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Color.secondary.opacity(0.14),
                                    in: Capsule(style: .continuous)
                                )
                        }

                        if entry.isPrimary {
                            Text("PRIMARY")
                                .font(.caption2.weight(.bold))
                                .tracking(0.55)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    Color.secondary.opacity(0.14),
                                    in: Capsule()
                                )
                        }
                    }

                    Text(entry.subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: - GitHub Provisioning Section

    @ViewBuilder
    private var githubProvisioningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Clone from GitHub")

            if let deviceFlow = github {
                deviceFlowCard(deviceFlow)
            } else if !repos.isEmpty {
                repoCatalogCard
            } else {
                addRepositoryTriggerCard
            }
        }
    }

    private func deviceFlowCard(_ deviceFlow: GithubDeviceStart) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("GitHub Device Authorization", systemImage: "key.radiowaves.forward")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Copy this one-time activation code and authorize the runner on GitHub. You can also grant access to additional organizations on that page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(deviceFlow.userCode)
                    .font(.title2.monospaced().weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Button {
                    copyDeviceCode(deviceFlow.userCode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: copiedDeviceCode ? "checkmark" : "doc.on.doc")
                            .font(.body.weight(.semibold))
                        Text(copiedDeviceCode ? "Copied" : "Copy")
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

            HStack(spacing: 12) {
                if let url = URL(string: deviceFlow.verificationUri) {
                    Link(destination: url) {
                        Label("Open GitHub", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }

                Button {
                    github = nil
                    pollToken = 0
                    statusText = nil
                    isAddingRepo = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var repoCatalogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter repositories (owner/repo)…", text: $repoFilter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !repoFilter.isEmpty {
                        Button {
                            repoFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

                Button("Close") {
                    repos = []
                    repoFilter = ""
                    isAddingRepo = false
                }
                .font(.subheadline.weight(.medium))
            }

            if filteredRepos.isEmpty {
                Text("No matching repositories found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRepos.enumerated()), id: \.element.id) { index, repo in
                        if index > 0 {
                            Divider().padding(.leading, 14)
                        }
                        githubRepoRow(repo)
                    }
                }
                .background(
                    Color(.tertiarySystemGroupedBackground).opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            HStack {
                Text("Missing an organization or private repo?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await reconnectGithub() }
                } label: {
                    Label("Grant More Permissions on GitHub…", systemImage: "key.fill")
                        .font(.caption.weight(.semibold))
                }
                .disabled(isBusy)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func githubRepoRow(_ repo: GithubRepoRecord) -> some View {
        let cloned = isAlreadyCloned(repo)
        return Button {
            Task { await clone(repo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cloned ? "checkmark.circle" : (repo.`private` ? "lock.doc" : "book.closed"))
                    .font(.body)
                    .foregroundStyle(cloned ? Color.secondary : Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.slug)
                        .font(.subheadline.weight(.medium).monospaced())
                        .foregroundStyle(cloned ? .secondary : .primary)
                        .lineLimit(1)

                    Text(cloned ? "Already on this runner" : (repo.`private` ? "Private" : "Public"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if cloned {
                    Text("INSTALLED")
                        .font(.caption2.weight(.bold))
                        .tracking(0.55)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Color.secondary.opacity(0.14),
                            in: Capsule()
                        )
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || cloned)
    }

    private var addRepositoryTriggerCard: some View {
        VStack(spacing: 0) {
            Button {
                Task { await startAddRepository() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Repository…")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(
                            hasGithubLink
                                ? "Browse repositories under @\(status?.githubLogin ?? "") and clone into a new workspace"
                                : "Authorize GitHub to clone a repository onto this runner"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || isLoading)

            if hasGithubLink {
                Divider().padding(.leading, 60)

                Button {
                    Task { await reconnectGithub() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Authorize More on GitHub…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Grant additional organizations or switch accounts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || isLoading)
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(title: "Device Pairing")

            VStack(spacing: 0) {
                Button {
                    isPairDevicePresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pair Another Device…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Show a pairing code or QR to authorize another iPad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy || isUnauthorized)

                Divider().padding(.leading, 56)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unpair This iPad")
                            .font(.subheadline.weight(.medium))
                        Text("Removes local token and cached projects for this runner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Forget Runner", role: .destructive) {
                        session.forgetEnrolledRunner(runner.id)
                        onClose()
                    }
                    .disabled(isBusy)
                }
                .padding(14)
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    // MARK: - Actions

    private func copyDeviceCode(_ code: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #endif
        copiedDeviceCode = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedDeviceCode = false
        }
    }

    private static func repoKey(owner: String, repo: String) -> String {
        "\(owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())/\(repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func isAlreadyCloned(_ repo: GithubRepoRecord) -> Bool {
        clonedRepoKeys.contains(Self.repoKey(owner: repo.owner, repo: repo.repo))
    }

    private func presentError(_ message: String) {
        if message == RunnerAuthCopy.unauthorized || message.contains("not authorized") {
            errorMessage = message
            toastMessage = nil
        } else {
            errorMessage = nil
            toastDismissTask?.cancel()
            toastMessage = message
            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if !Task.isCancelled {
                    toastMessage = nil
                }
            }
        }
    }

    private func client() -> RunnerCoreAPIClient? {
        let runnerId = session.enrolledRunners.first(where: {
            $0.id == runner.id || $0.url == RunnerURL.normalizeHTTP(runner.url)
        })?.id ?? runner.id
        let token = RunnerCredentialStore.token(runnerId: runnerId) ?? ""
        guard !token.isEmpty else { return nil }
        return RunnerCoreAPIClient(baseURLString: runner.url, apiToken: token)
    }

    @MainActor
    private func submitReAuth() async {
        let code = reAuthCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isReAuthBusy = true
        statusText = "Enrolling this device…"
        defer {
            isReAuthBusy = false
            statusText = nil
        }
        #if canImport(UIKit)
        let name = UIDevice.current.name
        #else
        let name = "iPad"
        #endif
        let client = RunnerCoreAPIClient(baseURLString: runner.url, apiToken: "")
        do {
            var enrolled = try await client.enrollDevice(code: code, deviceName: name)
            if enrolled.status == "pending", let enrollmentId = enrolled.enrollmentId {
                statusText = "Waiting for approval on another device…"
                for _ in 0..<300 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let polled = try await client.pollEnrollment(id: enrollmentId)
                    if polled.status == "complete" {
                        enrolled = polled
                        break
                    } else if polled.status == "denied" {
                        throw SetupEnrollError.denied
                    } else if polled.status == "expired" {
                        throw SetupEnrollError.expired
                    }
                }
            }
            guard enrolled.status == "complete",
                  let token = enrolled.token,
                  let runnerId = enrolled.runnerId else {
                throw SetupEnrollError.missingToken
            }
            RunnerCredentialStore.save(runnerId: runnerId, token: token)
            session.rememberEnrolledRunner(url: runner.url, runnerId: runnerId, label: runner.label)
            reAuthCode = ""
            errorMessage = nil
            await reload()
        } catch {
            presentError(RunnerAuthCopy.message(for: error))
        }
    }

    @MainActor
    private func reload() async {
        errorMessage = nil
        guard let client = client() else {
            isLoading = false
            presentError("This iPad has no token for this runner. Add it again.")
            return
        }
        isLoading = status == nil
        defer { isLoading = false }
        do {
            let next = try await client.setupSession()
            status = next
            if isAddingRepo && next.githubLogin != nil {
                repos = try await client.listGithubRepos()
            }
        } catch {
            presentError(RunnerAuthCopy.message(for: error))
        }
    }

    @MainActor
    private func startAddRepository() async {
        guard let client = client() else { return }
        isBusy = true
        errorMessage = nil
        toastMessage = nil
        isAddingRepo = true
        defer { isBusy = false }

        if hasGithubLink {
            do {
                statusText = "Loading repositories from GitHub…"
                defer { statusText = nil }
                repos = try await client.listGithubRepos()
                return
            } catch {
                // Token might be stale — fall through to device flow.
            }
        }

        await beginGithubDeviceFlow(client: client)
    }

    /// Force a new GitHub Device Flow so the user can grant more orgs / switch accounts.
    @MainActor
    private func reconnectGithub() async {
        guard let client = client() else { return }
        isBusy = true
        errorMessage = nil
        toastMessage = nil
        isAddingRepo = true
        repos = []
        defer { isBusy = false }
        await beginGithubDeviceFlow(client: client)
    }

    @MainActor
    private func beginGithubDeviceFlow(client: RunnerCoreAPIClient) async {
        do {
            github = try await client.startGithub()
            pollToken += 1
        } catch {
            statusText = nil
            isAddingRepo = false
            presentError(RunnerAuthCopy.message(for: error))
        }
    }

    @MainActor
    private func pollGithubIfNeeded() async {
        guard pollToken > 0, github != nil, let client = client() else { return }
        while !Task.isCancelled {
            do {
                let polled = try await client.pollGithub()
                if polled.status == "complete" {
                    statusText = nil
                    github = nil
                    repos = try await client.listGithubRepos()
                    await reload()
                    return
                }
                if polled.status != "pending" {
                    statusText = nil
                    presentError(polled.error ?? polled.status)
                    github = nil
                    isAddingRepo = false
                    return
                }
                let ms = max(polled.intervalMs ?? github?.intervalMs ?? 5_000, 1_000)
                try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
            } catch is CancellationError {
                return
            } catch {
                statusText = nil
                presentError(RunnerAuthCopy.message(for: error))
                github = nil
                isAddingRepo = false
                return
            }
        }
    }

    @MainActor
    private func clone(_ repo: GithubRepoRecord) async {
        guard !isAlreadyCloned(repo) else { return }
        guard let client = client() else { return }
        isBusy = true
        errorMessage = nil
        toastMessage = nil
        statusText = "Cloning \(repo.slug)…"
        defer {
            isBusy = false
            statusText = nil
        }
        do {
            let next = try await client.cloneGithubRepo(owner: repo.owner, repo: repo.repo)
            status = next
            repos = []
            repoFilter = ""
            isAddingRepo = false
            let workspaceId = next.workspaceId
                ?? next.workspaces?.first(where: {
                    $0.repo?.owner == repo.owner && $0.repo?.repo == repo.repo
                })?.id
                ?? "default"
            await openProject(workspaceId: workspaceId)
        } catch {
            presentError(RunnerAuthCopy.message(for: error))
        }
    }

    @MainActor
    private func openProject(workspaceId: String = "default") async {
        let runnerId = session.enrolledRunners.first(where: {
            $0.id == runner.id || $0.url == RunnerURL.normalizeHTTP(runner.url)
        })?.id ?? runner.id
        let token = RunnerCredentialStore.token(runnerId: runnerId) ?? ""
        guard !token.isEmpty else {
            presentError("This iPad has no token for this runner. Add it again.")
            return
        }
        isBusy = true
        errorMessage = nil
        toastMessage = nil
        statusText = "Opening workspace \(workspaceId)…"
        defer {
            isBusy = false
            statusText = nil
        }
        session.rememberEnrolledRunner(url: runner.url, runnerId: runnerId, label: runner.label)
        do {
            _ = try await VFSConnect.openSelfHosted(
                urlString: runner.url,
                token: token,
                workspaceId: workspaceId,
                engine: engine,
                vfs: vfs,
                session: session,
                agent: agent
            )
            RunnerConnectionPrefs.remember(url: runner.url)
            onOpened()
        } catch {
            presentError(RunnerAuthCopy.message(for: error))
        }
    }
}
