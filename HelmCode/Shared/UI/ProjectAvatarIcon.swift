//
//  ProjectAvatarIcon.swift
//  HelmCode
//
//  SwiftUI project avatars.
//  · ProjectAvatarIcon  — lists / chips (vector-like SwiftUI)
//  · ProjectAvatarImage — toolbar Menu labels (UIImage; custom views vanish there)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - List / chip

struct ProjectAvatarIcon: View {
    let identity: ProjectAvatarIdentity
    var size: CGFloat = ProjectAvatarMetrics.list

    init(identity: ProjectAvatarIdentity, size: CGFloat = ProjectAvatarMetrics.list) {
        self.identity = identity
        self.size = size
    }

    init(project: WorkspaceProject, size: CGFloat = ProjectAvatarMetrics.list) {
        self.identity = ProjectAvatarIdentity(project: project)
        self.size = size
    }

    init(name: String, seed: String? = nil, size: CGFloat = ProjectAvatarMetrics.list) {
        self.identity = ProjectAvatarIdentity(name: name, seed: seed)
        self.size = size
    }

    private var initials: String { identity.initials }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: ProjectAvatarMetrics.cornerRadius(for: size),
                style: .continuous
            )
            .fill(ProjectAvatarStyle.fillColor(for: identity.seed))

            Text(initials)
                .font(.system(
                    size: ProjectAvatarMetrics.fontSize(for: size, initialsCount: initials.count),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Project avatar")
        .accessibilityValue(initials)
    }
}

// MARK: - Toolbar / Menu-safe

/// Raster avatar so toolbar `Menu` labels render (Image + Text only).
struct ProjectAvatarImage: View {
    let identity: ProjectAvatarIdentity
    var size: CGFloat = ProjectAvatarMetrics.toolbar

    init(identity: ProjectAvatarIdentity, size: CGFloat = ProjectAvatarMetrics.toolbar) {
        self.identity = identity
        self.size = size
    }

    init(project: WorkspaceProject, size: CGFloat = ProjectAvatarMetrics.toolbar) {
        self.identity = ProjectAvatarIdentity(project: project)
        self.size = size
    }

    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: ProjectAvatarStyle.uiImage(identity: identity, side: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        #else
        ProjectAvatarIcon(identity: identity, size: size)
        #endif
    }
}
