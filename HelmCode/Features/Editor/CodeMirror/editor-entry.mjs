/**
 * CodeMirror 6 offline editor → window.HelmCodeEditor
 *
 * Theme rules (do not regress):
 *  1. baseTheme(layout) then oneDark — never mount another EditorView.theme after oneDark.
 *  2. Dark active-line wash is plain CSS on html[data-helm-scheme] (index.html), not a CM theme.
 */
import { EditorState } from "@codemirror/state"
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
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import {
  syntaxHighlighting,
  defaultHighlightStyle,
  foldGutter,
  foldKeymap,
  bracketMatching,
  indentOnInput,
  StreamLanguage,
} from "@codemirror/language"
import { closeBrackets, closeBracketsKeymap, autocompletion, completionKeymap } from "@codemirror/autocomplete"
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search"
import { lintKeymap } from "@codemirror/lint"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { json } from "@codemirror/lang-json"
import { markdown } from "@codemirror/lang-markdown"
import { cpp } from "@codemirror/lang-cpp"
import { swift } from "@codemirror/legacy-modes/mode/swift"
import { go } from "@codemirror/legacy-modes/mode/go"

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

// MARK: Theme (layout only — before oneDark)

function baseTheme(isDark) {
  return EditorView.theme(
    {
      "&": {
        height: "100%",
        width: "100%",
        maxWidth: "100%",
        fontSize: "14px",
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

// MARK: Extensions

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
    baseTheme(dark),
  ]

  // oneDark must be the last CM theme. Active-line wash is CSS, not a theme.
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
