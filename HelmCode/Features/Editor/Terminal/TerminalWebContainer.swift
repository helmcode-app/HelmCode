//
//  TerminalWebContainer.swift
//  HelmCode
//
//  UIKit host for the Terminal WKWebView: pins edges + reports real size changes
//  so xterm FitAddon can recompute cols/rows after panel / keyboard layout.
//

import UIKit
import WebKit

final class TerminalWebContainer: UIView {
    private(set) weak var webView: WKWebView?
    var onBoundsChange: (() -> Void)?
    private var lastSize: CGSize = .zero

    func embed(_ webView: WKWebView) {
        self.webView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applySystemBackground()
        clipsToBounds = true
    }

    func applySystemBackground() {
        backgroundColor = .systemBackground
        webView?.backgroundColor = .systemBackground
        webView?.scrollView.backgroundColor = .systemBackground
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // Ignore sub-pixel jitter; fire on real panel resizes.
        if abs(size.width - lastSize.width) > 0.5
            || abs(size.height - lastSize.height) > 0.5
        {
            lastSize = size
            onBoundsChange?()
        }
    }
}
