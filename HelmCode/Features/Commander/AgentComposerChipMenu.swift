//
//  AgentComposerChipMenu.swift
//  HelmCode
//
//  Small glass chip Menu used by the composer (branch / mode).
//

import SwiftUI

struct AgentComposerChipMenu<Content: View>: View {
    let title: String
    let systemImage: String
    var disabled: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Label {
                HStack(spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(disabled)
    }
}

/// Glass chip that opens a sheet (model picker) — same visual language as chip menus.
struct AgentComposerChipButton: View {
    let title: String
    let systemImage: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                HStack(spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(disabled)
    }
}
