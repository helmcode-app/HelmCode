//
//  HelmSearchFieldChrome.swift
//  HelmCode
//
//  Single reusable iOS search-field chrome for SwiftUI hosts (sidebar Search, etc.).
//
//  Editor find/replace (CodeMirror) cannot host SwiftUI; mirror the same metrics in
//  Features/Editor/CodeMirror/index.html CSS tokens + `helmFieldWrap()` in editor-entry.mjs:
//    capsule · fieldHeight 36 · padX 12 · optionGap 6 · clusterGap 6
//

import SwiftUI

// MARK: - Metrics

enum HelmSearchFieldMetrics {
    /// Fixed outer height (sidebar Search + editor Find / Replace).
    static let fieldHeight: CGFloat = 36
    /// Leading icon ↔ text ↔ trailing options.
    static let clusterSpacing: CGFloat = 6
    /// Aa ↔ W (↔ .*).
    static let optionSpacing: CGFloat = 6
    /// Horizontal inset; slightly roomier for capsule ends.
    static let horizontalPadding: CGFloat = 12
}

// MARK: - Field shell

extension View {
    /// Fixed-height secondary-fill capsule field shell (system search style).
    func helmSearchFieldChrome() -> some View {
        padding(.horizontal, HelmSearchFieldMetrics.horizontalPadding)
            .frame(height: HelmSearchFieldMetrics.fieldHeight)
            .background(Color(.secondarySystemFill), in: Capsule(style: .continuous))
    }
}

// MARK: - Search field

/// Shared search / find text field: optional leading icon, text, trailing options.
struct HelmSearchField<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var showsMagnifyingGlass: Bool = true
    var onSubmit: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        text: Binding<String>,
        placeholder: String = "Search",
        showsMagnifyingGlass: Bool = true,
        onSubmit: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self._text = text
        self.placeholder = placeholder
        self.showsMagnifyingGlass = showsMagnifyingGlass
        self.onSubmit = onSubmit
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: HelmSearchFieldMetrics.clusterSpacing) {
            if showsMagnifyingGlass {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            TextField(placeholder, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { onSubmit?() }

            trailing()
        }
        .helmSearchFieldChrome()
    }
}

extension HelmSearchField where Trailing == EmptyView {
    init(
        text: Binding<String>,
        placeholder: String = "Search",
        showsMagnifyingGlass: Bool = true,
        onSubmit: (() -> Void)? = nil
    ) {
        self.init(
            text: text,
            placeholder: placeholder,
            showsMagnifyingGlass: showsMagnifyingGlass,
            onSubmit: onSubmit,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Match options

/// Clickable monospaced option (Aa / W / .*): accent when on, secondary when off.
/// `.plain` — text color only (no fill / border on press).
struct SearchMatchOptionLabel: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Trailing cluster of match options with standard spacing.
struct SearchMatchOptionCluster: View {
    @Binding var caseSensitive: Bool
    @Binding var matchWholeWord: Bool
    var showsRegexp: Bool = false
    @Binding var matchRegexp: Bool

    init(
        caseSensitive: Binding<Bool>,
        matchWholeWord: Binding<Bool>,
        matchRegexp: Binding<Bool> = .constant(false),
        showsRegexp: Bool = false
    ) {
        self._caseSensitive = caseSensitive
        self._matchWholeWord = matchWholeWord
        self._matchRegexp = matchRegexp
        self.showsRegexp = showsRegexp
    }

    var body: some View {
        HStack(spacing: HelmSearchFieldMetrics.optionSpacing) {
            SearchMatchOptionLabel(title: "Aa", help: "Match Case", isOn: $caseSensitive)
            SearchMatchOptionLabel(title: "W", help: "Match Whole Word", isOn: $matchWholeWord)
            if showsRegexp {
                SearchMatchOptionLabel(title: ".*", help: "Use Regular Expression", isOn: $matchRegexp)
            }
        }
    }
}
