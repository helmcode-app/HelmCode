//
//  PlainToolbarLabel.swift
//  HelmCode
//
//  Non-interactive toolbar title text (no button chrome).
//

import SwiftUI

struct PlainToolbarLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
    }
}
