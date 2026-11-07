//
//  SidebarNavigatorTabBar.swift
//  HelmCode
//
//  System segmented control. Owned here so a settings sheet cannot replay the
//  selection indicator — SwiftUI Picker does that on every column layout.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SidebarNavigatorTabBar: View {
    @Binding var selection: SidebarNavigator
    var badges: [SidebarNavigator: Int] = [:]

    var body: some View {
        SidebarSegmentedControl(selection: $selection, badges: badges)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
    }
}

#if canImport(UIKit)
private struct SidebarSegmentedControl: UIViewRepresentable {
    @Binding var selection: SidebarNavigator
    var badges: [SidebarNavigator: Int]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> QuietSegmentedControl {
        let control = QuietSegmentedControl(frame: .zero)
        control.apportionsSegmentWidthsByContent = false
        UIView.performWithoutAnimation {
            for (index, nav) in SidebarNavigator.allCases.enumerated() {
                control.insertSegment(with: UIImage(systemName: nav.systemImage), at: index, animated: false)
            }
            control.selectedSegmentIndex = Self.index(of: selection)
        }
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: QuietSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let index = Self.index(of: selection)
        guard control.selectedSegmentIndex != index else {
            control.accessibilityValue = accessibilityValue(for: selection)
            return
        }
        UIView.performWithoutAnimation {
            control.selectedSegmentIndex = index
        }
        control.accessibilityValue = accessibilityValue(for: selection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuietSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 36)
    }

    private static func index(of nav: SidebarNavigator) -> Int {
        SidebarNavigator.allCases.firstIndex(of: nav) ?? 0
    }

    private func accessibilityValue(for nav: SidebarNavigator) -> String {
        if let badge = badges[nav], badge > 0 {
            return "\(nav.title), \(badge)"
        }
        return nav.title
    }

    final class Coordinator: NSObject {
        var selection: Binding<SidebarNavigator>

        init(selection: Binding<SidebarNavigator>) {
            self.selection = selection
        }

        @objc func changed(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard SidebarNavigator.allCases.indices.contains(index) else { return }
            let next = SidebarNavigator.allCases[index]
            guard selection.wrappedValue != next else { return }
            selection.wrappedValue = next
        }
    }
}

/// Selection pill must not animate when a sheet lays the column out.
private final class QuietSegmentedControl: UISegmentedControl {
    override func layoutSubviews() {
        UIView.performWithoutAnimation {
            super.layoutSubviews()
        }
    }
}
#else
private struct SidebarSegmentedControl: View {
    @Binding var selection: SidebarNavigator
    var badges: [SidebarNavigator: Int]

    var body: some View {
        Picker("Navigator", selection: $selection) {
            ForEach(SidebarNavigator.allCases) { nav in
                Image(systemName: nav.systemImage).tag(nav)
            }
        }
        .pickerStyle(.segmented)
    }
}
#endif
