//
//  TerminalAccessoryBar.swift
//  HelmCode
//
//  Tactile on-screen accessory bar for iPad software keyboard terminal operations.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct TerminalAccessoryBar: View {
    @ObservedObject var controller: TerminalSessionController

    private let quickCommands = [
        ("git status", "git status\n"),
        ("git diff", "git diff\n"),
        ("ls -la", "ls -la\n"),
        ("clear", "clear\n"),
        ("pwd", "pwd\n"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Control keys
                    keyButton(.esc, tint: .orange)
                    keyButton(.tab, tint: .accentColor)
                    keyButton(.ctrlC, tint: .red)
                    keyButton(.ctrlD)
                    keyButton(.ctrlL)

                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 2)

                    // Directional keys
                    keyButton(.left)
                    keyButton(.down)
                    keyButton(.up)
                    keyButton(.right)

                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 2)

                    // Common symbols
                    keyButton(.pipe)
                    keyButton(.tilde)
                    keyButton(.slash)
                    keyButton(.hyphen)

                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 2)

                    // Quick command menu
                    Menu {
                        ForEach(quickCommands, id: \.0) { label, cmd in
                            Button(label) {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                controller.sendInput(cmd)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Snippets")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.leading, 10)
                .padding(.vertical, 6)
            }

            trailingTools
                .padding(.trailing, 10)
                .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Font size + clear pinned to the trailing edge of the accessory bar.
    private var trailingTools: some View {
        HStack(spacing: 6) {
            toolChip(systemName: "textformat.size.smaller", label: "Decrease font size") {
                controller.decreaseFontSize()
            }
            toolChip(systemName: "textformat.size.larger", label: "Increase font size") {
                controller.increaseFontSize()
            }
            toolChip(systemName: "trash", label: "Clear terminal buffer") {
                controller.clear()
            }
        }
    }

    private func toolChip(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 28)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func keyButton(_ key: TerminalKey, tint: Color? = nil) -> some View {
        Button {
            controller.sendKey(key)
        } label: {
            Text(key.rawValue)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint ?? Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    (tint?.opacity(0.12) ?? Color(.tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
