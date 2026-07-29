//
//  SidebarView.swift
//  HelmCode
//
//  System NavigationSplitView sidebar — workspace tree + pinned Settings.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    var onOpenSettings: () -> Void

    var body: some View {
        List(selection: $session.selectedFileID) {
            Section {
                projectPicker
                connectionBadge
            } header: {
                Text("Workspace")
            }

            if let project = session.selectedProject {
                Section {
                    OutlineGroup(project.root.children, children: \.directoryChildren) { node in
                        Label {
                            Text(node.name)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: node.systemImage)
                                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                        }
                        .tag(node.id)
                        .accessibilityLabel(node.path)
                    }
                } header: {
                    HStack {
                        Text("Files")
                        Spacer()
                        Text(project.defaultBranch)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(project.remote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            List {
                Section {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityHint("Opens app settings")
                }
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .frame(maxHeight: 56)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Rows

    private var projectPicker: some View {
        Picker("Project", selection: $session.selectedProjectID) {
            ForEach(session.projects) { project in
                Text(project.name).tag(Optional(project.id))
            }
        }
        .pickerStyle(.menu)
        .onChange(of: session.selectedProjectID) { oldValue, newValue in
            guard oldValue != newValue else { return }
            session.selectedFileID = nil
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            ConnectionStatusDot(state: engine.connectionState)
            VStack(alignment: .leading, spacing: 2) {
                Text(sidebarStatusTitle)
                    .font(.subheadline.weight(.medium))
                Text(modeLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var sidebarStatusTitle: String {
        switch engine.connectionState {
        case .online: return "Backend online"
        case .checking: return "Checking…"
        case .offline(let msg): return "Offline — \(msg)"
        case .unknown: return "Not connected"
        }
    }

    private var modeLine: String {
        if let health = engine.health {
            return "\(health.mode.rawValue) · v\(health.version) · \(health.activeTasks) active"
        }
        return engine.helmMode.rawValue
    }
}
