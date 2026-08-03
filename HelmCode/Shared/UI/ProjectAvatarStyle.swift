//
//  ProjectAvatarStyle.swift
//  HelmCode
//
//  IDEA-style project avatar: initials from name + stable fill from seed.
//  Initials apply to the glyph only — never replace the project title in UI.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

// MARK: - Identity

/// Inputs for avatar rendering (name for letters, seed for color).
struct ProjectAvatarIdentity: Hashable, Sendable {
    let name: String
    /// Prefer `project.id` so color survives renames.
    let seed: String

    init(name: String, seed: String? = nil) {
        self.name = name
        self.seed = seed ?? name
    }

    init(project: WorkspaceProject) {
        self.name = project.displayName
        self.seed = project.id
    }

    var initials: String {
        ProjectAvatarStyle.initials(from: name)
    }
}

// MARK: - Metrics

enum ProjectAvatarMetrics {
    static let list: CGFloat = 28
    static let chip: CGFloat = 22
    static let toolbar: CGFloat = 18
    static let menu: CGFloat = 16

    static func cornerRadius(for side: CGFloat) -> CGFloat {
        max(4, side * 0.22)
    }

    static func fontSize(for side: CGFloat, initialsCount: Int) -> CGFloat {
        initialsCount <= 1 ? side * 0.42 : side * 0.36
    }
}

// MARK: - Style

enum ProjectAvatarStyle {
    // MARK: Initials

    /// Single word → 1 letter; multiple words → first + last word initials.
    static func initials(from name: String) -> String {
        let words = words(from: name)
        guard let first = words.first else { return "?" }
        if words.count == 1 { return letter(from: first) }
        guard let last = words.last else { return letter(from: first) }
        return letter(from: first) + letter(from: last)
    }

    static func words(from name: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in name {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(contentsOf: splitCamelCase(current))
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(contentsOf: splitCamelCase(current))
        }
        return tokens.filter { !$0.isEmpty }
    }

    // MARK: Color

    static func colorIndex(for seed: String) -> Int {
        let hash = seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return Int(hash % UInt64(rgbPalette.count))
    }

    static func fillColor(for seed: String) -> Color {
        let rgb = rgbPalette[colorIndex(for: seed)]
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    #if canImport(UIKit)
    static func fillUIColor(for seed: String) -> UIColor {
        let rgb = rgbPalette[colorIndex(for: seed)]
        return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    /// Raster for toolbar / `Menu` labels (custom SwiftUI views are often dropped there).
    static func uiImage(
        identity: ProjectAvatarIdentity,
        side: CGFloat,
        scale: CGFloat = 3
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        )
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let path = UIBezierPath(
                roundedRect: rect,
                cornerRadius: ProjectAvatarMetrics.cornerRadius(for: side)
            )
            fillUIColor(for: identity.seed).setFill()
            path.fill()

            let text = identity.initials as NSString
            let font = UIFont.systemFont(
                ofSize: ProjectAvatarMetrics.fontSize(for: side, initialsCount: text.length),
                weight: .semibold
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                withAttributes: attrs
            )
        }
    }
    #endif

    // MARK: Private

    private struct RGB: Sendable {
        let r: Double
        let g: Double
        let b: Double
    }

    /// Single source of truth for SwiftUI + UIKit fills.
    private static let rgbPalette: [RGB] = [
        RGB(r: 0.90, g: 0.32, b: 0.30),
        RGB(r: 0.95, g: 0.55, b: 0.20),
        RGB(r: 0.95, g: 0.72, b: 0.15),
        RGB(r: 0.35, g: 0.70, b: 0.30),
        RGB(r: 0.15, g: 0.68, b: 0.55),
        RGB(r: 0.20, g: 0.60, b: 0.90),
        RGB(r: 0.35, g: 0.45, b: 0.90),
        RGB(r: 0.60, g: 0.40, b: 0.85),
        RGB(r: 0.85, g: 0.35, b: 0.65),
        RGB(r: 0.45, g: 0.55, b: 0.65),
    ]

    private static func splitCamelCase(_ token: String) -> [String] {
        guard token.count > 1 else { return [token] }
        var parts: [String] = []
        var current = ""
        let chars = Array(token)

        for i in chars.indices {
            let c = chars[i]
            if i > 0, c.isUppercase {
                let prev = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || (prev.isUppercase && nextIsLower) {
                    if !current.isEmpty {
                        parts.append(current)
                        current = ""
                    }
                }
            }
            current.append(c)
        }
        if !current.isEmpty {
            parts.append(current)
        }
        return parts.isEmpty ? [token] : parts
    }

    private static func letter(from word: String) -> String {
        guard let first = word.first else { return "" }
        return String(first).uppercased()
    }
}
