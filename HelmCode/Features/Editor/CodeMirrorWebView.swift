//
//  CodeMirrorWebView.swift
//  HelmCode
//
//  WKWebView subclass: system edit menu + custom CodeMirror commands.
//  Only `buildMenu` — never also install UIMenuItems (duplicates under Share).
//

import UIKit
import WebKit

/// Offline CodeMirror host web view with system context/edit menu extensions.
final class CodeMirrorWebView: WKWebView {
    /// Invoked for custom menu actions; id matches `CodeMirrorCommand.rawValue`.
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
