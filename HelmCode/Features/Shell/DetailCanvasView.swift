//
//  DetailCanvasView.swift
//  HelmCode
//
//  Detail column — Editor + Commander (Xcode-style inspector).
//

import SwiftUI

struct DetailCanvasView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    var onOpenSettings: () -> Void

    @AppStorage(AppStorageKey.showEditor) private var showEditor = true
    @AppStorage(AppStorageKey.showCommander) private var showCommander = true
    @AppStorage(AppStorageKey.commanderWidth) private var commanderWidth = LayoutMetrics.defaultCommanderWidth

    var body: some View {
        canvas
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { detailToolbar }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if showEditor {
            ToolbarItem(placement: .topBarLeading) {
                PlainToolbarLabel(title: editorFileTitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        // Trailing: first item is rightmost → toggle, then "Commander" to its left.
        ToolbarItem(placement: .topBarTrailing) {
            InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
        }
        if showCommander {
            ToolbarItem(placement: .topBarTrailing) {
                PlainToolbarLabel(title: "Commander")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            HStack(spacing: 0) {
                if showEditor {
                    EditorCanvasView(
                        project: session.selectedProject,
                        file: session.selectedFile,
                        engine: engine
                    )
                    .frame(minWidth: LayoutMetrics.editorMinWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                }

                if showEditor && showCommander {
                    ColumnResizeHandle(
                        width: $commanderWidth,
                        range: LayoutMetrics.commanderWidthRange,
                        affectsTrailingColumn: true
                    )
                    .transition(.opacity)
                }

                if showCommander {
                    CommanderView(engine: engine)
                        .frame(width: showEditor ? resolvedCommanderWidth(total: total) : nil)
                        .frame(maxWidth: showEditor ? resolvedCommanderWidth(total: total) : .infinity)
                        .frame(maxHeight: .infinity)
                        .transition(trailingSlide)
                }

                if !showEditor && !showCommander {
                    emptyPlaceholder
                        .transition(.opacity)
                }
            }
            .frame(width: total, height: proxy.size.height, alignment: .leading)
            .clipped()
            .animation(LayoutMetrics.panelSlideAnimation, value: showCommander)
            .animation(LayoutMetrics.panelSlideAnimation, value: showEditor)
        }
    }

    private var trailingSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Actions

    private func toggleCommander() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            if showCommander {
                if !showEditor { showEditor = true }
                showCommander = false
            } else {
                showCommander = true
            }
        }
    }

    private var editorFileTitle: String {
        if let file = session.selectedFile, !file.isDirectory {
            return file.name
        }
        return "Editor"
    }

    private var emptyPlaceholder: some View {
        ContentUnavailableView {
            Label("No detail columns", systemImage: "rectangle.split.2x1")
        } description: {
            Text("Show the Editor or Commander from the toolbar or Settings.")
        } actions: {
            Button("Show Commander") {
                withAnimation(LayoutMetrics.panelSlideAnimation) { showCommander = true }
            }
            .buttonStyle(.borderedProminent)
            Button("Open Settings", action: onOpenSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolvedCommanderWidth(total: CGFloat) -> CGFloat {
        let range = LayoutMetrics.commanderWidthRange
        let w = min(range.upperBound, max(range.lowerBound, commanderWidth))
        let reserved = (showEditor ? Double(LayoutMetrics.editorMinWidth) : 0) + 16
        let maxAllowed = max(range.lowerBound, Double(total) - reserved)
        return CGFloat(min(w, maxAllowed))
    }
}
