//
//  AgentComposerPromptEditor.swift
//  HelmCode
//
//  Composer prompt field: TextEditor + placeholder.
//  Return sends · Option+Return newline · picker keys when `/` or `@` is open.
//

import SwiftUI

/// Hardware-keyboard routing while the `/` / `@` menu is open.
struct AgentComposerMenuKeys {
    var isActive: Bool
    var onMove: (Int) -> Void
    var onConfirm: () -> Bool
    var onCancel: () -> Void
}

struct AgentComposerPromptEditor: View {
    @Binding var text: String
    var selection: Binding<TextSelection?>
    var placeholder: String
    var isDisabled: Bool
    var canSend: Bool
    var promptFocused: FocusState<Bool>.Binding
    var onSend: () -> Void
    var onInsertNewline: () -> Void
    var menuKeys: AgentComposerMenuKeys? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text, selection: selection)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44, maxHeight: 140)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .focused(promptFocused)
                .disabled(isDisabled)
                // Hardware keyboard: Return → newline · Command+Return → send · menu confirm when open.
                .onKeyPress(keys: [.return]) { press in
                    if menuKeys?.isActive == true {
                        _ = menuKeys?.onConfirm()
                        return .handled
                    }
                    if press.modifiers.contains(.command) {
                        if canSend {
                            onSend()
                            return .handled
                        }
                        return .handled
                    }
                    if press.modifiers.contains(.option) {
                        onInsertNewline()
                        return .handled
                    }
                    // Regular Return inserts a newline into the TextEditor.
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    guard menuKeys?.isActive == true else { return .ignored }
                    menuKeys?.onMove(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard menuKeys?.isActive == true else { return .ignored }
                    menuKeys?.onMove(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard menuKeys?.isActive == true else { return .ignored }
                    menuKeys?.onCancel()
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard menuKeys?.isActive == true else { return .ignored }
                    _ = menuKeys?.onConfirm()
                    return .handled
                }

            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
    }
}
