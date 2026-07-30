//
//  EditorKeyboardShortcuts.swift
//  HelmCode
//
//  Single source of truth for CodeMirror / editor shortcut help UI.
//  Keep in sync with Features/Editor/CodeMirror/editor-entry.mjs (helmEditorKeymap).
//

import SwiftUI

// MARK: - Model

struct EditorShortcut: Identifiable, Hashable, Sendable {
    let id: String
    let keys: String
    let action: String

    init(keys: String, action: String) {
        self.id = "\(keys)|\(action)"
        self.keys = keys
        self.action = action
    }
}

struct EditorShortcutSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [EditorShortcut]

    init(title: String, items: [EditorShortcut]) {
        self.id = title
        self.title = title
        self.items = items
    }
}

enum EditorKeyboardShortcutsCatalog {
    /// Settings → About → Keyboard Shortcuts.
    static let sections: [EditorShortcutSection] = [
        EditorShortcutSection(title: "Font Size", items: [
            .init(keys: "⌘ +  /  ⌘ =", action: "Larger font"),
            .init(keys: "⌘ -", action: "Smaller font"),
            .init(keys: "⌘ 0", action: "Reset font (14px)"),
        ]),
        EditorShortcutSection(title: "Edit", items: [
            .init(keys: "⌘ Z", action: "Undo"),
            .init(keys: "⌘ ⇧ Z  /  ⌘ Y", action: "Redo"),
            .init(keys: "⌘ /", action: "Toggle line comment"),
            .init(keys: "⌘ ]  /  ⌘ [", action: "Indent / outdent"),
            .init(keys: "⌘ ⇧ K", action: "Delete line"),
            .init(keys: "⌥ ↑  /  ⌥ ↓", action: "Move line up / down"),
            .init(keys: "⌘ ↵", action: "Insert line below"),
            .init(keys: "Tab  /  ⇧ Tab", action: "Indent / outdent selection"),
        ]),
        EditorShortcutSection(title: "Selection & Navigation", items: [
            .init(keys: "⌘ A", action: "Select all"),
            .init(keys: "⌘ L", action: "Select line"),
            .init(keys: "⌘ ←  /  ⌘ →", action: "Line start / end"),
            .init(keys: "⌘ ↑  /  ⌘ ↓", action: "Document start / end"),
            .init(keys: "Esc", action: "Clear selection / close find"),
        ]),
        EditorShortcutSection(title: "Bookmarks", items: [
            .init(keys: "⌘ F2", action: "Toggle bookmark on current line"),
            .init(keys: "⌘ ⌥ B", action: "Toggle bookmark on current line"),
            .init(keys: "Gutter click", action: "Toggle bookmark on that line"),
        ]),
        EditorShortcutSection(title: "Find & Fold", items: [
            .init(keys: "⌘ F", action: "Find"),
            .init(keys: "⌘ ⌥ [  /  ⌘ ⌥ ]", action: "Fold / unfold all"),
            .init(keys: "⌘ ⌥ .", action: "Toggle fold at cursor"),
        ]),
    ]
}

// MARK: - Reference page

/// Pushed from Settings → About (not on the editor toolbar).
struct EditorKeyboardShortcutsView: View {
    var body: some View {
        List {
            Section {
                Text("Active when the code editor is focused (hardware keyboard on iPad).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(EditorKeyboardShortcutsCatalog.sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        LabeledContent {
                            Text(item.action)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text(item.keys)
                                .font(.body.monospaced())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.action), \(item.keys)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Keyboard Shortcuts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        EditorKeyboardShortcutsView()
    }
}
