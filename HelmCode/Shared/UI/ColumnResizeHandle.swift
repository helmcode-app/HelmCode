//
//  ColumnResizeHandle.swift
//  HelmCode
//
//  Desktop-style drag divider between split columns.
//

import SwiftUI

struct ColumnResizeHandle: View {
    @Binding var width: Double
    var range: ClosedRange<Double>
    /// When `true`, dragging right shrinks the bound column (column sits on the trailing side).
    var affectsTrailingColumn: Bool = true

    @State private var dragStartWidth: Double?

    var body: some View {
        Divider()
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let start = dragStartWidth ?? width
                        let delta = affectsTrailingColumn
                            ? -value.translation.width
                            : value.translation.width
                        width = clamp(start + delta)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy(duration: 0.2)) {
                    if width <= range.lowerBound + 8 {
                        width = min(range.upperBound, max(range.lowerBound, (range.lowerBound + range.upperBound) / 2))
                    } else {
                        width = range.lowerBound
                    }
                }
            }
            .accessibilityLabel("Resize column")
            .accessibilityAdjustableAction { direction in
                let step: Double = 24
                switch direction {
                case .increment:
                    width = clamp(width + (affectsTrailingColumn ? -step : step))
                case .decrement:
                    width = clamp(width + (affectsTrailingColumn ? step : -step))
                @unknown default:
                    break
                }
            }
    }

    private func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
