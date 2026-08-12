//
//  OpenProjectHostedPlaceholder.swift
//  HelmCode
//
//  Reserved “Hosted” tab content for Open Project (not yet available).
//

import SwiftUI

struct OpenProjectHostedPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("HelmCode Hosted")
                .font(.title3.weight(.semibold))
            Text("Connect to managed runners in the cloud. This option will be available in a future release.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 20)
    }
}
