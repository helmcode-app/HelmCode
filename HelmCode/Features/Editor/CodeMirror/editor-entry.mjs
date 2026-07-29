/**
 * CodeMirror 6 offline editor → window.HelmCodeEditor
 *
 * Theme rules (do not regress):
 *  1. baseTheme(layout) then oneDark — never mount another EditorView.theme after oneDark.
 *  2. Dark active-line wash is plain CSS on html[data-helm-scheme] (index.html), not a CM theme.
 *  3. Font-size uses a Compartment (not a theme after oneDark).
 */
import { EditorState, Compartment } from "@codemirror/state"
import {
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLineGutter,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
  highlightActiveLine,
} from "@codemirror/view"
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  indentMore,
  indentLess,
  deleteLine,
  moveLineDown,
  moveLineUp,
  selectAll,
  selectLine,
  toggleComment,
  insertBlankLine,
  cursorLineBoundaryBackward,
  cursorLineBoundaryForward,
  simplifySelection,
} from "@codemirror/commands"
import {
  syntaxHighlighting,
  defaultHighlightStyle,
  foldGutter,
  foldKeymap,
  bracketMatching,
  indentOnInput,
  StreamLanguage,
  toggleFold,
  foldAll,
  unfoldAll,
} from "@codemirror/language"
import { closeBrackets, closeBracketsKeymap, autocompletion, completionKeymap } from "@codemirror/autocomplete"
import { searchKeymap, highlightSelectionMatches, openSearchPanel, closeSearchPanel } from "@codemirror/search"
import { lintKeymap } from "@codemirror/lint"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { json } from "@codemirror/lang-json"
import { markdown } from "@codemirror/lang-markdown"
import { cpp } from "@codemirror/lang-cpp"
import { swift } from "@codemirror/legacy-modes/mode/swift"
import { go } from "@codemirror/legacy-modes/mode/go"

// MARK: Font size (IDE zoom)

const FONT_DEFAULT = 14
const FONT_MIN = 10
const FONT_MAX = 28
const FONT_STEP = 1

/** Survives setDocument(); only reset when the web view is recreated. */
let fontSizePx = FONT_DEFAULT
const fontSizeCompartment = new Compartment()

function clampFontSize(n) {
  return Math.min(FONT_MAX, Math.max(FONT_MIN, n))
}

/** Layout-only theme for current size — kept *before* oneDark via compartment slot. */
function fontSizeTheme(size) {
  return EditorView.theme({
    "&": { fontSize: `${size}px` },
  })
}

function setFontSize(view, size) {
  fontSizePx = clampFontSize(size)
  view.dispatch({
    effects: fontSizeCompartment.reconfigure(fontSizeTheme(fontSizePx)),
  })
  view.requestMeasure()
  return true
}

function bumpFontSize(view, delta) {
  return setFontSize(view, fontSizePx + delta * FONT_STEP)
}

// MARK: Language

function languageExtension(lang) {
  switch (lang) {
    case "swift":
      return StreamLanguage.define(swift)
    case "go":
      return StreamLanguage.define(go)
    case "ts":
    case "typescript":
      return javascript({ typescript: true })
    case "js":
    case "javascript":
      return javascript()
    case "json":
      return json()
    case "md":
    case "markdown":
      return markdown()
    case "cpp":
    case "c":
      return cpp()
    default:
      return []
  }
}

// MARK: Theme (layout only — before oneDark; no fontSize here)

function baseTheme(isDark) {
  return EditorView.theme(
    {
      "&": {
        height: "100%",
        width: "100%",
        maxWidth: "100%",
        backgroundColor: "transparent",
      },
      ".cm-scroller": {
        fontFamily:
          "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        lineHeight: "1.45",
        overflowX: "hidden",
        overflowY: "auto",
      },
      ".cm-content": {
        padding: "12px 0",
        caretColor: isDark ? "#fff" : "#000",
        whiteSpace: "pre-wrap",
        wordBreak: "break-word",
        maxWidth: "100%",
        boxSizing: "border-box",
      },
      ".cm-line": {
        maxWidth: "100%",
        paddingRight: "12px",
      },
      ".cm-gutters": {
        backgroundColor: "transparent",
        border: "none",
        color: isDark ? "#6b7280" : "#9ca3af",
        flexShrink: "0",
      },
      "&.cm-focused": {
        outline: "none",
      },
    },
    { dark: isDark },
  )
}

/** Drives index.html active-line CSS (CM has no stable .cm-dark class). */
function setShellScheme(dark) {
  document.documentElement.dataset.helmScheme = dark ? "dark" : "light"
}

// MARK: Keymaps

/**
 * Desktop-IDE-style bindings on top of CM defaults.
 * Zoom uses preventDefault so the host doesn’t steal Mod-= / Mod--.
 */
function helmEditorKeymap() {
  return keymap.of([
    // Font size (VS Code / Xcode style)
    { key: "Mod-=", run: (v) => bumpFontSize(v, 1), preventDefault: true },
    { key: "Mod-+", run: (v) => bumpFontSize(v, 1), preventDefault: true },
    { key: "Mod--", run: (v) => bumpFontSize(v, -1), preventDefault: true },
    { key: "Mod-_", run: (v) => bumpFontSize(v, -1), preventDefault: true },
    { key: "Mod-0", run: (v) => setFontSize(v, FONT_DEFAULT), preventDefault: true },

    // Common edit / structure (also in defaultKeymap; listed for explicit Mac IDE parity)
    { key: "Mod-a", run: selectAll },
    { key: "Mod-l", run: selectLine },
    { key: "Mod-/", run: toggleComment },
    { key: "Mod-]", run: indentMore },
    { key: "Mod-[", run: indentLess },
    { key: "Shift-Mod-k", run: deleteLine },
    { key: "Alt-ArrowUp", run: moveLineUp },
    { key: "Alt-ArrowDown", run: moveLineDown },
    { key: "Mod-Enter", run: insertBlankLine },
    // Xcode-style: ⌘← / ⌘→ jump to line bounds (overrides word-hop).
    { key: "Mod-ArrowLeft", run: cursorLineBoundaryBackward },
    { key: "Mod-ArrowRight", run: cursorLineBoundaryForward },

    // Fold (⌘⌥[ / ⌘⌥])
    { key: "Mod-Alt-[", run: foldAll },
    { key: "Mod-Alt-]", run: unfoldAll },
    { key: "Mod-Alt-.", run: toggleFold },

    // Search (also in searchKeymap); Esc closes panel then clears selection.
    { key: "Mod-f", run: openSearchPanel },
    {
      key: "Escape",
      run: (v) => closeSearchPanel(v) || simplifySelection(v),
    },
  ])
}

function editorKeymap() {
  return keymap.of([
    ...closeBracketsKeymap,
    ...defaultKeymap,
    ...searchKeymap,
    ...historyKeymap,
    ...foldKeymap,
    ...completionKeymap,
    ...lintKeymap,
    indentWithTab,
  ])
}

// MARK: Extensions

function makeExtensions({ language, dark, readOnly }) {
  const exts = [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    history(),
    foldGutter(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    bracketMatching(),
    closeBrackets(),
    autocompletion(),
    rectangularSelection(),
    crosshairCursor(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    EditorView.lineWrapping,
    editorKeymap(),
    // Higher precedence than defaults so zoom / IDE keys win when overlapping.
    helmEditorKeymap(),
    baseTheme(dark),
    // Font size compartment before oneDark (layout-only theme).
    fontSizeCompartment.of(fontSizeTheme(fontSizePx)),
  ]

  // oneDark must be the last CM *color* theme.
  if (dark) {
    exts.push(oneDark)
  }

  if (readOnly) {
    exts.push(EditorState.readOnly.of(true))
  }

  const lang = languageExtension(language)
  if (!Array.isArray(lang) && lang) {
    exts.push(lang)
  }

  return exts
}

// MARK: Bootstrap

let view = null

function boot() {
  const root = document.getElementById("editor")
  if (!root) return

  setShellScheme(true)

  view = new EditorView({
    state: EditorState.create({
      doc: "",
      extensions: makeExtensions({
        language: "swift",
        dark: true,
        readOnly: false,
      }),
    }),
    parent: root,
  })

  if (typeof ResizeObserver !== "undefined") {
    new ResizeObserver(() => view?.requestMeasure()).observe(root)
  }

  window.HelmCodeEditor = {
    setDocument({ text, language, dark, readOnly }) {
      if (!view) return
      const isDark = !!dark
      setShellScheme(isDark)
      view.setState(
        EditorState.create({
          doc: typeof text === "string" ? text : "",
          extensions: makeExtensions({
            language: language || "plain",
            dark: isDark,
            readOnly: !!readOnly,
          }),
        }),
      )
      requestAnimationFrame(() => view.requestMeasure())
    },
    relayout() {
      view?.requestMeasure()
    },
    getDocument() {
      return view ? view.state.doc.toString() : ""
    },
    getFontSize() {
      return fontSizePx
    },
    setFontSize(size) {
      if (!view) return fontSizePx
      setFontSize(view, Number(size) || FONT_DEFAULT)
      return fontSizePx
    },
    focus() {
      view?.focus()
    },
  }

  try {
    window.webkit?.messageHandlers?.helmEditor?.postMessage({ type: "ready" })
  } catch (_) {}
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot)
} else {
  boot()
}
