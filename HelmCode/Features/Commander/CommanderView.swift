//
//  CommanderView.swift
//  HelmCode
//
//  AI agent chat — hosted in the system `.inspector` column.
//  Cursor-style sessions + composer (AgentCommandPanel).
//

import SwiftUI

struct CommanderView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession

    var body: some View {
        AgentCommandPanel(
            agent: agent,
            session: session,
            httpEngine: engine
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
