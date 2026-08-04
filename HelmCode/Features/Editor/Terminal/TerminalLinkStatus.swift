//
//  TerminalLinkStatus.swift
//  HelmCode
//
//  Connection status for the WebSSH panel chrome (from JS bridge `status` messages).
//

import SwiftUI

enum TerminalLinkStatus: String, Sendable, Equatable {
    case info
    case ok
    case err

    init(kind: String) {
        self = TerminalLinkStatus(rawValue: kind) ?? .info
    }

    var foreground: Color {
        switch self {
        case .ok: return .green
        case .err: return .red
        case .info: return .secondary
        }
    }
}
