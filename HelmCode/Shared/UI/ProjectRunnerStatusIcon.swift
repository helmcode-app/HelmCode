//
//  ProjectRunnerStatusIcon.swift
//  HelmCode
//
//  Trailing glyph for a project’s runner reachability (list rows only).
//

import SwiftUI

/// Trailing / compact glyph for `ProjectRunnerReachability`.
struct ProjectRunnerStatusIcon: View {
    let status: ProjectRunnerReachability
    var compact: Bool = true

    var body: some View {
        Group {
            switch status {
            case .none:
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
            case .checking:
                ProgressView()
                    .controlSize(compact ? .mini : .small)
            case .online:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .offline:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .imageScale(compact ? .medium : .large)
        .accessibilityLabel(status.accessibilityLabel)
        .help(status.accessibilityLabel)
    }
}
