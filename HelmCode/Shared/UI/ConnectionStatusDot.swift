//
//  ConnectionStatusDot.swift
//  HelmCode
//
//  Shared backend connection indicator (HTTP open-core).
//

import SwiftUI

struct ConnectionStatusDot: View {
    let state: BackendConnectionState

    var body: some View {
        Circle()
            .fill(state.statusDotColor)
            .frame(width: 8, height: 8)
    }
}

/// Dot + short title used in Commander / compact chrome.
struct BackendConnectionLabel: View {
    let state: BackendConnectionState
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 6) {
            ConnectionStatusDot(state: state)
            Text(state.shortTitle)
                .font(font)
                .foregroundStyle(state.statusForeground)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension BackendConnectionState {
    var statusDotColor: Color {
        switch self {
        case .online: return .green
        case .checking: return .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }

    /// Title color: secondary when healthy, red when offline.
    var statusForeground: Color {
        isOnline ? Color.secondary : Color.red
    }
}
