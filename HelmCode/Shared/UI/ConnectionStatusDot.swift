//
//  ConnectionStatusDot.swift
//  HelmCode
//
//  Shared backend connection indicator.
//

import SwiftUI

struct ConnectionStatusDot: View {
    let state: BackendConnectionState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .online: return .green
        case .checking: return .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}
