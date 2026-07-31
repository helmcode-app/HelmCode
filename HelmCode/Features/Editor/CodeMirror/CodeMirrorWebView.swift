//
//  CodeMirrorWebView.swift
//  HelmCode
//
//  WKWebView subclass: system edit menu + custom CodeMirror commands.
//  Only `buildMenu` — never also install UIMenuItems (duplicates under Share).
//
//  Hardware ⌘F is often claimed by the system before WKWebView/JS sees it;
//  UIKeyCommand + wantsPriorityOverSystemBehavior routes it into the editor.
//

import UIKit
import WebKit

/// Offline CodeMirror host web view with system context/edit menu extensions.
final class CodeMirrorWebView: WKWebView {
    /// Invoked for custom menu actions / hardware key commands.
    var onCustomCommand: ((CodeMirrorCommand) -> Void)?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        configureChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shared chrome for the editor host (clear background, vertical scroll only).
    private func configureChrome() {
        isOpaque = false
        backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceHorizontal = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        #if DEBUG
        if #available(iOS 16.4, *) {
            isInspectable = true
        }
        #endif
    }

    // MARK: - Hardware keyboard (iPad)

    /// Claim editor shortcuts that the system would otherwise swallow (esp. ⌘F).
    override var keyCommands: [UIKeyCommand]? {
        [
            Self.priorityCommand(
                title: "Find",
                input: "f",
                modifiers: .command,
                action: #selector(helmFind(_:))
            ),
            Self.priorityCommand(
                title: "Find and Replace",
                input: "f",
                modifiers: [.command, .alternate],
                action: #selector(helmFindReplace(_:))
            ),
            Self.priorityCommand(
                title: "Find Next",
                input: "g",
                modifiers: .command,
                action: #selector(helmFindNext(_:))
            ),
            Self.priorityCommand(
                title: "Find Previous",
                input: "g",
                modifiers: [.command, .shift],
                action: #selector(helmFindPrevious(_:))
            ),
            Self.priorityCommand(
                title: "Save",
                input: "s",
                modifiers: .command,
                action: #selector(helmSave(_:))
            ),
        ]
    }

    private static func priorityCommand(
        title: String,
        input: String,
        modifiers: UIKeyModifierFlags,
        action: Selector
    ) -> UIKeyCommand {
        let command = UIKeyCommand(title: title, action: action, input: input, modifierFlags: modifiers)
        command.wantsPriorityOverSystemBehavior = true
        command.discoverabilityTitle = title
        return command
    }

    @objc private func helmFind(_ sender: Any?) {
        onCustomCommand?(.find)
    }

    @objc private func helmFindReplace(_ sender: Any?) {
        onCustomCommand?(.findReplace)
    }

    @objc private func helmFindNext(_ sender: Any?) {
        onCustomCommand?(.findNext)
    }

    @objc private func helmFindPrevious(_ sender: Any?) {
        onCustomCommand?(.findPrevious)
    }

    @objc private func helmSave(_ sender: Any?) {
        onCustomCommand?(.save)
    }

    /// Backup path when key commands are not delivered but presses reach this view.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            let mods = key.modifierFlags.intersection([.command, .shift, .alternate, .control])
            let chars = key.charactersIgnoringModifiers.lowercased()
            if chars == "s", mods.contains(.command) {
                onCustomCommand?(.save)
                return
            }
            if chars == "f", mods.contains(.command) {
                onCustomCommand?(mods.contains(.alternate) ? .findReplace : .find)
                return
            }
            if chars == "g", mods.contains(.command) {
                onCustomCommand?(mods.contains(.shift) ? .findPrevious : .findNext)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    // MARK: - Context menu

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        let children = CodeMirrorCommand.contextMenuItems.map { item in
            UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { [weak self] _ in
                self?.onCustomCommand?(item.command)
            }
        }
        let custom = UIMenu(title: "", options: .displayInline, children: children)

        if builder.menu(for: .standardEdit) != nil {
            builder.insertSibling(custom, afterMenu: .standardEdit)
        } else {
            builder.insertChild(custom, atEndOfMenu: .root)
        }
    }
}
