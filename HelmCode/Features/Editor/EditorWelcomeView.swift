//
//  EditorWelcomeView.swift
//  HelmCode
//
//  Center-column start page when no project is open (VS Code / Xcode style).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EditorWelcomeView: View {
    @ObservedObject var session: WorkspaceSession
    var onOpenSettings: (() -> Void)?

    @State private var isProjectPickerPresented = false

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
        .sheet(isPresented: $isProjectPickerPresented) {
            projectPickerSheet
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
                    systemImage: "folder",
                    detail: "Choose from available workspaces"
                ) {
                    isProjectPickerPresented = true
                }

                cardDivider

                startRow(
                    title: "Clone Repository…",
                    systemImage: "arrow.down.doc",
                    detail: "Coming soon",
                    isEnabled: false
                ) {}

                cardDivider

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

            if session.recentProjects.isEmpty {
                Text("No recent projects yet. Open a project to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                InsetGroupedCard {
                    ForEach(Array(session.recentProjects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { cardDivider }
                        recentProjectRow(project)
                    }
                }
            }
        }
    }

    // MARK: - Project picker sheet

    private var projectPickerSheet: some View {
        NavigationStack {
            List(session.projects) { project in
                Button {
                    session.openProject(project.id)
                    isProjectPickerPresented = false
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .foregroundStyle(.primary)
                            Text("\(project.defaultBranch)  ·  \(project.remote)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .navigationTitle("Open Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isProjectPickerPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Rows

    private var cardDivider: some View {
        Divider().padding(.leading, 44)
    }

    private func startRow(
        title: String,
        systemImage: String,
        detail: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            WelcomeListRow(
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
            WelcomeListRow(
                title: project.name,
                subtitle: "\(project.defaultBranch)  ·  \(project.remote)",
                subtitleMonospaced: true,
                systemImage: "folder.fill"
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                session.removeFromRecents(project.id)
            } label: {
                Label("Remove from Recents", systemImage: "trash")
            }
        }
    }
}

#Preview {
    EditorWelcomeView(session: WorkspaceSession())
}
