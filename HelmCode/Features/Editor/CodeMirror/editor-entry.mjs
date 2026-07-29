import { EditorState } from "@codemirror/state"
import { EditorView, keymap, lineNumbers, highlightActiveLineGutter, highlightSpecialChars, drawSelection, dropCursor, rectangularSelection, crosshairCursor, highlightActiveLine, placeholder } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { syntaxHighlighting, defaultHighlightStyle, foldGutter, foldKeymap, bracketMatching, indentOnInput } from "@codemirror/language"
import { closeBrackets, closeBracketsKeymap, autocompletion, completionKeymap } from "@codemirror/autocomplete"
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search"
import { lintKeymap } from "@codemirror/lint"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { json } from "@codemirror/lang-json"
import { markdown } from "@codemirror/lang-markdown"
import { cpp } from "@codemirror/lang-cpp"
import { StreamLanguage } from "@codemirror/language"
import { swift } from "@codemirror/legacy-modes/mode/swift"
import { go } from "@codemirror/legacy-modes/mode/go"

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

function baseTheme(isDark) {
  return EditorView.theme({
    "&": {
      height: "100%",
      fontSize: "14px",
      backgroundColor: "transparent"
    },
    ".cm-scroller": {
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      lineHeight: "1.45",
      overflow: "auto"
    },
    ".cm-content": {
      padding: "12px 0",
      caretColor: isDark ? "#fff" : "#000"
    },
    ".cm-gutters": {
      backgroundColor: "transparent",
      border: "none",
      color: isDark ? "#6b7280" : "#9ca3af"
    },
    "&.cm-focused": {
      outline: "none"
    }
  }, { dark: isDark })
}

function makeExtensions({ language, dark, readOnly, wrap }) {
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
    keymap.of([
      ...closeBracketsKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
      ...lintKeymap,
      indentWithTab
    ]),
    baseTheme(dark)
  ]

  if (wrap) {
    exts.push(EditorView.lineWrapping)
  }
  if (dark) {
    exts.push(oneDark)
  }
  if (readOnly) {
    exts.push(EditorState.readOnly.of(true))
  }

  const lang = languageExtension(language)
  if (Array.isArray(lang)) {
    // empty
  } else if (lang) {
    exts.push(lang)
  }

  return exts
}

let view = null

function boot() {
  const root = document.getElementById("editor")
  if (!root) return

  const state = EditorState.create({
    doc: "",
    extensions: makeExtensions({
      language: "swift",
      dark: true,
      readOnly: false,
      wrap: true
    })
  })

  view = new EditorView({
    state,
    parent: root
  })

  window.HelmCodeEditor = {
    setDocument({ text, language, dark, readOnly, wrap }) {
      if (!view) return
      const doc = typeof text === "string" ? text : ""
      view.setState(
        EditorState.create({
          doc,
          extensions: makeExtensions({
            language: language || "plain",
            dark: !!dark,
            readOnly: !!readOnly,
            wrap: wrap !== false
          })
        })
      )
    },
    getDocument() {
      return view ? view.state.doc.toString() : ""
    },
    focus() {
      view?.focus()
    }
  }

  // Notify native host that CM is ready.
  try {
    window.webkit?.messageHandlers?.helmEditor?.postMessage({ type: "ready" })
  } catch (_) {}
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot)
} else {
  boot()
}
