//
//  ProjectSettingsPresentation.swift
//  HelmCode
//
//  Shared sheet presentation for Project Settings (welcome / browse / sidebar).
//

import SwiftUI

extension View {
    /// Present `ProjectSettingsSheet` when `projectID` is non-nil.
    func projectSettingsSheet(
        projectID: Binding<WorkspaceProject.ID?>,
        session: WorkspaceSession,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine,
        agent: AgentNetworkEngine
    ) -> some View {
        sheet(
            isPresented: Binding(
                get: { projectID.wrappedValue != nil },
                set: { if !$0 { projectID.wrappedValue = nil } }
            )
        ) {
            if let id = projectID.wrappedValue {
                ProjectSettingsSheet(
                    session: session,
                    engine: engine,
                    vfs: vfs,
                    agent: agent,
                    projectID: id,
                    isPresented: Binding(
                        get: { projectID.wrappedValue != nil },
                        set: { if !$0 { projectID.wrappedValue = nil } }
                    )
                )
            }
        }
    }
}
