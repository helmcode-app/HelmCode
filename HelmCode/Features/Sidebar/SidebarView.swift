//
//  SidebarView.swift
//  HelmCode
//
//  NavigationSplitView sidebar shell:
//  • No project — Projects list
//  • Project open — navigator tabs (Files / Search / Bookmarks / SCM)
//  • Top bar — system sidebarToggle; global VFS status only when a project is open
//  • Projects list — per-row runner reachability (list only)
//  • Bottom — system safeAreaBar Settings row (material / soft edge)
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    var onOpenSettings: () -> Void

    @AppStorage(AppStorageKey.sidebarNavigator) private var navigatorRaw = SidebarNavigator.files.rawValue

    @State private var dialog: SidebarTreeDialog?
    @State private var nameDraft = ""
    @State private var commitMessage = ""

    private var navigator: Binding<SidebarNavigator> {
        Binding(
            get: { SidebarNavigator(rawValue: navigatorRaw) ?? .files },
            set: { navigatorRaw = $0.rawValue }
        )
    }

    private var currentNavigator: SidebarNavigator {
        SidebarNavigator(rawValue: navigatorRaw) ?? .files
    }

    var body: some View {
        Group {
            if let project = session.selectedProject {
                projectNavigator(project)
            } else {
                projectsList
            }
        }
        // Empty inline title keeps a standard nav bar so custom + system
        // toolbar items share the same bar metrics / baseline.
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Trailing: first item is closest to the edge (system toggle).
            DefaultToolbarItem(kind: .sidebarToggle, placement: .topBarTrailing)
            // Global VFS status only while a project is open (hide on welcome / project list).
            if session.selectedProject != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    SidebarVFSStatusIcon(vfs: vfs)
                }
            }
        }
        .helmSidebarBottomChrome {
            SidebarSettingsBar(action: onOpenSettings)
        }
        .task(id: session.projects.map(\.id).joined(separator: ",")) {
            runnerStatus.refresh(projects: session.projects, engine: engine)
        }
        .alert(dialog?.title ?? "", isPresented: dialogPresented) {
            dialogButtons
        } message: {
            if let dialog {
                Text(dialog.message)
            }
        }
        .alert(
            "Can't complete action",
            isPresented: Binding(
                get: { session.lastTreeError != nil },
                set: { if !$0 { session.lastTreeError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.lastTreeError = nil }
        } message: {
            Text(session.lastTreeError ?? "")
        }
    }

    // MARK: - Project navigator

    private func projectNavigator(_ project: WorkspaceProject) -> some View {
        VStack(spacing: 0) {
            SidebarNavigatorTabBar(
                selection: navigator,
                badges: navigatorBadges
            )
            navigatorContent(project)
        }
    }

    private var navigatorBadges: [SidebarNavigator: Int] {
        var badges: [SidebarNavigator: Int] = [:]
        let bookmarkCount = session.activeBookmarks.count
        if bookmarkCount > 0 {
            badges[.bookmarks] = bookmarkCount
        }
        if let count = session.sourceControl?.changeCount, count > 0 {
            badges[.sourceControl] = count
        }
        return badges
    }

    @ViewBuilder
    private func navigatorContent(_ project: WorkspaceProject) -> some View {
        switch currentNavigator {
        case .files:
            SidebarFilesView(
                session: session,
                vfs: vfs,
                project: project,
                onPresentDialog: present(_:)
            )
        case .search:
            SidebarSearchView(session: session, project: project)
        case .bookmarks:
            SidebarBookmarksView(session: session)
        case .sourceControl:
            SidebarSourceControlView(
                session: session,
                commitMessage: $commitMessage
            )
        }
    }

    // MARK: - Projects (no open project)

    private var projectsList: some View {
        List {
            Section {
                ForEach(session.projects) { project in
                    Button {
                        session.openProject(project.id)
                    } label: {
                        ProjectListLabel(
                            project: project,
                            secondary: .remote,
                            runnerStatus: runnerStatus.displayStatus(
                                for: project,
                                engine: engine,
                                vfs: vfs
                            )
                        )
                    }
                }
            } header: {
                Text("Projects")
            } footer: {
                Text("Open a project to browse files, or use the welcome page.")
                    .font(.caption2)
            }
        }
        .helmSidebarListStyle()
    }

    // MARK: - Tree dialogs

    private var dialogPresented: Binding<Bool> {
        Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )
    }

    @ViewBuilder
    private var dialogButtons: some View {
        if let dialog {
            if dialog.usesNameField {
                TextField("Name", text: $nameDraft)
                Button("Cancel", role: .cancel) { self.dialog = nil }
                Button(dialog.confirmTitle) { confirmDialog() }
            } else {
                Button("Cancel", role: .cancel) { self.dialog = nil }
                Button("Delete", role: .destructive) { confirmDialog() }
            }
        } else {
            Button("OK", role: .cancel) {}
        }
    }

    private func present(_ value: SidebarTreeDialog) {
        nameDraft = value.defaultNameDraft
        dialog = value
    }

    private func confirmDialog() {
        defer { dialog = nil }
        dialog?.apply(to: session, nameDraft: nameDraft)
    }
}
