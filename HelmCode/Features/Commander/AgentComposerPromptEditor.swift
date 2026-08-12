//
//  AgentComposerPromptEditor.swift
//  HelmCode
//
//  Composer prompt field: TextEditor + placeholder + Return / Option+Return keys.
//

import SwiftUI

struct AgentComposerPromptEditor: View {
    @Binding var text: String
    var selection: Binding<TextSelection?>
    var placeholder: String
    var isDisabled: Bool
    var canSend: Bool
    var promptFocused: FocusState<Bool>.Binding
    var onSend: () -> Void
    var onInsertNewline: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text, selection: selection)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .focused(promptFocused)
                .disabled(isDisabled)
                // Hardware keyboard: Return → send · Option+Return → newline (Cursor-style).
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.option) {
                        onInsertNewline()
                        return .handled
                    }
                    // Ignore other modifiers (⌘/⇧) so they don't also send by accident.
                    if !press.modifiers.isEmpty {
                        return .ignored
                    }
                    if canSend {
                        onSend()
                        return .handled
                    }
                    return .handled
                }

            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }
}
