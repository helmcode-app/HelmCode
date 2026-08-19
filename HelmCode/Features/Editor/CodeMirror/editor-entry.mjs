/**
 * CodeMirror 6 offline editor → window.HelmCodeEditor
 *
 * Theme rules (do not regress):
 *  1. baseTheme(layout) then oneDark — never mount another EditorView.theme after oneDark.
 *  2. Dark active-line wash is plain CSS on html[data-helm-scheme] (index.html), not a CM theme.
 *  3. Font-size uses a Compartment (not a theme after oneDark).
 */
import { EditorState, Compartment, StateField, StateEffect, RangeSet } from "@codemirror/state"
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
  GutterMarker,
  gutter,
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
import {
  search,
  searchKeymap,
  highlightSelectionMatches,
  openSearchPanel,
  closeSearchPanel,
  findNext,
  findPrevious,
  replaceNext,
  replaceAll,
  getSearchQuery,
  setSearchQuery,
  SearchQuery,
} from "@codemirror/search"
import { lintKeymap } from "@codemirror/lint"
import { oneDark } from "@codemirror/theme-one-dark"
import { unifiedMergeView } from "@codemirror/merge"
import { javascript } from "@codemirror/lang-javascript"
import { json } from "@codemirror/lang-json"
import { markdown } from "@codemirror/lang-markdown"
import { cpp } from "@codemirror/lang-cpp"
import { html } from "@codemirror/lang-html"
import { css } from "@codemirror/lang-css"
import { python } from "@codemirror/lang-python"
import { rust } from "@codemirror/lang-rust"
import { java } from "@codemirror/lang-java"
import { xml } from "@codemirror/lang-xml"
import { sql } from "@codemirror/lang-sql"
import { yaml } from "@codemirror/lang-yaml"
import { php } from "@codemirror/lang-php"
import { sass } from "@codemirror/lang-sass"
import { swift } from "@codemirror/legacy-modes/mode/swift"
import { go } from "@codemirror/legacy-modes/mode/go"
import { shell } from "@codemirror/legacy-modes/mode/shell"
import { dockerFile } from "@codemirror/legacy-modes/mode/dockerfile"
import { toml } from "@codemirror/legacy-modes/mode/toml"
import { ruby } from "@codemirror/legacy-modes/mode/ruby"
import { lua } from "@codemirror/legacy-modes/mode/lua"
import { kotlin, csharp } from "@codemirror/legacy-modes/mode/clike"

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
    case "gomod":
      // go.mod / go.sum — shell-like tokens are good enough for readability.
      return StreamLanguage.define(shell)
    case "ts":
    case "typescript":
      return javascript({ typescript: true })
    case "tsx":
      return javascript({ typescript: true, jsx: true })
    case "js":
    case "javascript":
      return javascript()
    case "jsx":
      return javascript({ jsx: true })
    case "json":
      return json()
    case "md":
    case "markdown":
      return markdown()
    case "html":
      return html()
    case "css":
      return css()
    case "scss":
      return sass()
    case "cpp":
      return cpp()
    case "c":
      return cpp()
    case "py":
    case "python":
      return python()
    case "rs":
    case "rust":
      return rust()
    case "java":
      return java()
    case "kotlin":
      return StreamLanguage.define(kotlin)
    case "csharp":
      return StreamLanguage.define(csharp)
    case "xml":
      return xml()
    case "yml":
    case "yaml":
      return yaml()
    case "toml":
      return StreamLanguage.define(toml)
    case "sql":
      return sql()
    case "sh":
    case "shell":
      return StreamLanguage.define(shell)
    case "docker":
      return StreamLanguage.define(dockerFile)
    case "ruby":
      return StreamLanguage.define(ruby)
    case "php":
      return php()
    case "lua":
      return StreamLanguage.define(lua)
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

// MARK: Line bookmarks (Xcode-style)

const setBookmarksEffect = StateEffect.define()

const bookmarkMarker = new (class extends GutterMarker {
  toDOM() {
    const el = document.createElement("div")
    el.className = "cm-bookmark-mark"
    el.title = "Bookmark"
    el.setAttribute("aria-label", "Bookmark")
    // Filled bookmark glyph (SF Symbol–like), color via CSS `currentColor`.
    el.innerHTML =
      '<svg class="cm-bookmark-icon" viewBox="0 0 16 16" width="12" height="12" aria-hidden="true">' +
      '<path fill="currentColor" d="M3.5 1.5A1.5 1.5 0 0 1 5 0h6a1.5 1.5 0 0 1 1.5 1.5v13.1a.75.75 0 0 1-1.16.63L8 12.35l-3.34 2.88A.75.75 0 0 1 3.5 14.6Z"/>' +
      "</svg>"
    return el
  }
})()

const bookmarkField = StateField.define({
  create() {
    return RangeSet.empty
  },
  update(set, tr) {
    set = set.map(tr.changes)
    for (const e of tr.effects) {
      if (e.is(setBookmarksEffect)) set = e.value
    }
    return set
  },
})

function bookmarksFromLines(state, lines) {
  const marks = []
  const max = state.doc.lines
  const unique = [...new Set((lines || []).map((n) => Math.floor(Number(n))).filter((n) => n >= 1 && n <= max))]
  unique.sort((a, b) => a - b)
  for (const n of unique) {
    const line = state.doc.line(n)
    marks.push(bookmarkMarker.range(line.from))
  }
  return RangeSet.of(marks, true)
}

function applyBookmarkLines(view, lines) {
  view.dispatch({
    effects: setBookmarksEffect.of(bookmarksFromLines(view.state, lines)),
  })
}

function postToggleBookmark(line, lineText) {
  try {
    window.webkit?.messageHandlers?.helmEditor?.postMessage({
      type: "toggleBookmark",
      line,
      lineText: lineText || "",
    })
  } catch (_) {}
}

function postToHost(payload) {
  try {
    window.webkit?.messageHandlers?.helmEditor?.postMessage(payload)
  } catch (_) {}
}

/** 1-based line / column of the primary selection head (caret). */
function cursorFromState(state) {
  const head = state.selection.main.head
  const line = state.doc.lineAt(head)
  return { line: line.number, column: head - line.from + 1 }
}

function postCursorPosition(target) {
  if (!target) return
  const { line, column } = cursorFromState(target.state)
  postToHost({ type: "cursorPosition", line, column })
}

function cursorPositionExtension() {
  let lastLine = -1
  let lastCol = -1
  return EditorView.updateListener.of((update) => {
    if (!update.selectionSet) return
    const { line, column } = cursorFromState(update.state)
    if (line === lastLine && column === lastCol) return
    lastLine = line
    lastCol = column
    postToHost({ type: "cursorPosition", line, column })
  })
}

/** Notify Swift of document edits (debounced). Host must not call setDocument for these. */
let documentChangeTimer = null
/** True while applying a host-driven hot reload (skip echo documentChange). */
let suppressDocumentChange = false

function documentChangeExtension() {
  return EditorView.updateListener.of((update) => {
    if (!update.docChanged || update.view.state.readOnly || suppressDocumentChange) return
    if (documentChangeTimer) clearTimeout(documentChangeTimer)
    documentChangeTimer = setTimeout(() => {
      documentChangeTimer = null
      if (suppressDocumentChange) return
      postToHost({
        type: "documentChange",
        text: update.state.doc.toString(),
      })
    }, 120)
  })
}

function postSaveRequest() {
  if (!view) return true
  // Flush pending debounce so host has latest text before save.
  if (documentChangeTimer) {
    clearTimeout(documentChangeTimer)
    documentChangeTimer = null
  }
  postToHost({
    type: "save",
    text: view.state.doc.toString(),
  })
  return true
}

/** Ask host to toggle; host pushes updated markers via setBookmarks. */
function requestToggleBookmarkAt(view, lineNumber) {
  const line = view.state.doc.line(lineNumber)
  postToggleBookmark(line.number, line.text)
  return true
}

function toggleBookmarkAtCursor(view) {
  // Multi-line selection: bookmark the first line (range start), not the caret/head.
  const { from, to } = view.state.selection.main
  const line = view.state.doc.lineAt(Math.min(from, to))
  return requestToggleBookmarkAt(view, line.number)
}

function bookmarkGutter() {
  return gutter({
    class: "cm-bookmark-gutter",
    markers: (v) => v.state.field(bookmarkField),
    initialSpacer: () => bookmarkMarker,
    domEventHandlers: {
      mousedown(view, line) {
        requestToggleBookmarkAt(view, line.number)
        return true
      },
    },
  })
}

function goToLine(view, lineNumber) {
  const n = Math.min(Math.max(1, Math.floor(Number(lineNumber) || 1)), view.state.doc.lines)
  const line = view.state.doc.line(n)
  view.dispatch({
    selection: { anchor: line.from },
    effects: EditorView.scrollIntoView(line.from, { y: "center" }),
  })
  view.focus()
}

/** 1-based line currently at the top of the editor viewport. */
function firstVisibleLineNumber(view) {
  try {
    const rect = view.scrollDOM.getBoundingClientRect()
    const pos = view.posAtCoords({ x: rect.left + 12, y: rect.top + 4 })
    if (pos == null) return 1
    return view.state.doc.lineAt(pos).number
  } catch (_) {
    return 1
  }
}

/** Pin a line to the top of the viewport (hot reload). */
function scrollLineToTop(view, lineNumber) {
  const n = Math.min(Math.max(1, Math.floor(Number(lineNumber) || 1)), view.state.doc.lines)
  const line = view.state.doc.line(n)
  view.dispatch({
    effects: EditorView.scrollIntoView(line.from, { y: "start", yMargin: 0 }),
  })
}

/** Shared prefix length (UTF-16 code units). */
function commonPrefixLength(a, b) {
  const n = Math.min(a.length, b.length)
  let i = 0
  while (i < n && a.charCodeAt(i) === b.charCodeAt(i)) i++
  return i
}

/** Shared suffix length, excluding the first `skip` code units of each string. */
function commonSuffixLength(a, b, skip) {
  const max = Math.min(a.length - skip, b.length - skip)
  let i = 0
  while (
    i < max &&
    a.charCodeAt(a.length - 1 - i) === b.charCodeAt(b.length - 1 - i)
  ) {
    i++
  }
  return i
}

/**
 * Hot-reload body without rebuilding EditorState.
 * Uses prefix/suffix diff so CM only re-highlights the changed span (less flash),
 * keeps pixel scroll, and suppresses documentChange echo to Swift.
 */
function replaceDocumentText(text, { preserveTopLine = true } = {}) {
  if (!view) return
  const next = typeof text === "string" ? text : ""
  const current = view.state.doc.toString()
  if (current === next) return

  const scrollTop = view.scrollDOM.scrollTop
  const scrollLeft = view.scrollDOM.scrollLeft
  const topLine = preserveTopLine ? firstVisibleLineNumber(view) : 1

  const pref = commonPrefixLength(current, next)
  const suff = commonSuffixLength(current, next, pref)
  const from = pref
  const to = current.length - suff
  const insert = next.slice(pref, next.length - suff)

  suppressDocumentChange = true
  if (documentChangeTimer) {
    clearTimeout(documentChangeTimer)
    documentChangeTimer = null
  }
  try {
    view.dispatch({
      changes: { from, to, insert },
      // Keep user selection mapping; no scroll effect here.
      userEvent: "input.remote",
    })
    // Pixel restore first — cheaper and less flicker than scrollIntoView on every paint.
    view.scrollDOM.scrollTop = scrollTop
    view.scrollDOM.scrollLeft = scrollLeft
  } finally {
    // Keep suppress until after any sync updateListener runs.
    queueMicrotask(() => {
      suppressDocumentChange = false
    })
  }

  if (preserveTopLine) {
    // If lines above the viewport changed height, re-pin the previous top line.
    requestAnimationFrame(() => {
      if (!view) return
      const nowTop = firstVisibleLineNumber(view)
      if (nowTop !== topLine) {
        scrollLineToTop(view, topLine)
      }
    })
  }
}

// MARK: Find / replace panel (VS Code widget chrome)
// Field shell metrics mirror Shared/UI/HelmSearchFieldChrome.swift (capsule).

/** Consumed by the next panel construction: ⌘⌥F opens with Replace expanded. */
let pendingOpenWithReplace = false

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "className") node.className = value
    else if (key === "text") node.textContent = value
    else if (key.startsWith("on") && typeof value === "function") {
      node.addEventListener(key.slice(2).toLowerCase(), value)
    } else if (value === true) node.setAttribute(key, "")
    else if (value !== false && value != null) node.setAttribute(key, String(value))
  }
  for (const child of children) {
    if (child == null) continue
    node.appendChild(typeof child === "string" ? document.createTextNode(child) : child)
  }
  return node
}

function helmTextField({ name, placeholder, value, mainField = false }) {
  return el("input", {
    className: "helm-search-input",
    name,
    type: "search",
    placeholder,
    "aria-label": placeholder,
    ...(mainField ? { "main-field": "true" } : {}),
    autocomplete: "off",
    autocorrect: "off",
    autocapitalize: "off",
    spellcheck: "false",
    value: value || "",
  })
}

/** Capsule field shell — same role as SwiftUI `helmSearchFieldChrome()`. */
function helmFieldWrap(input, trailing = []) {
  const kids = [input]
  if (trailing.length) {
    kids.push(el("div", { className: "helm-search-toggles" }, trailing))
  }
  return el("div", { className: "helm-search-field-wrap" }, kids)
}

/** Aa / W / .* — plain monospaced label; accent when on (matches SearchMatchOptionLabel). */
function helmMatchOption(label, title, on) {
  const btn = el("button", {
    type: "button",
    className: "helm-search-toggle" + (on ? " is-on" : ""),
    title,
    "aria-label": title,
    "aria-pressed": on ? "true" : "false",
    text: label,
  })
  btn.addEventListener("click", (e) => {
    e.preventDefault()
    const next = btn.getAttribute("aria-pressed") !== "true"
    setMatchOptionPressed(btn, next)
    btn.dispatchEvent(new CustomEvent("helm-toggle", { bubbles: true }))
  })
  return btn
}

function setMatchOptionPressed(btn, on) {
  btn.setAttribute("aria-pressed", on ? "true" : "false")
  btn.classList.toggle("is-on", on)
}

function isMatchOptionOn(btn) {
  return btn.getAttribute("aria-pressed") === "true"
}

function helmSearchButton({ label, title, onClick, className = "helm-search-btn" }) {
  return el("button", {
    type: "button",
    className,
    title,
    "aria-label": title,
    text: label,
    onClick: (e) => {
      e.preventDefault()
      onClick()
    },
  })
}

/**
 * Sync expand/collapse on panel root DOM.
 * Class + hidden + display — CSS `display: grid` would otherwise ignore [hidden].
 */
function syncReplaceOpenDOM(root, open) {
  if (!root) return
  root.classList.toggle("is-replace-open", open)
  const replaceRow = root.querySelector(".helm-search-row-replace")
  const expand = root.querySelector(".helm-search-expand")
  if (replaceRow) {
    replaceRow.hidden = !open
    replaceRow.setAttribute("aria-hidden", open ? "false" : "true")
    replaceRow.style.display = open ? "" : "none"
  }
  if (expand) {
    expand.setAttribute("aria-expanded", open ? "true" : "false")
    expand.textContent = open ? "▼" : "▶"
    expand.title = open ? "Hide Replace" : "Show Replace"
  }
}

function focusPanelField(panel, wantReplace) {
  if (!panel) return
  const input = wantReplace
    ? panel.querySelector("input[name=replace]") || panel.querySelector("input[name=search]")
    : panel.querySelector("input[name=search]")
  if (!input) return
  input.focus()
  if (typeof input.select === "function") input.select()
}

/**
 * VS Code–style find widget:
 * · Fixed width, top-right · ⌘F find-only · chevron / ⌘⌥F expands Replace
 */
class HelmSearchPanel {
  constructor(view) {
    this.view = view
    const q = getSearchQuery(view.state)
    this.replaceExpanded = !!pendingOpenWithReplace && !view.state.readOnly
    pendingOpenWithReplace = false

    this.searchField = helmTextField({
      name: "search",
      placeholder: "Find",
      value: q.search,
      mainField: true,
    })
    this.replaceField = helmTextField({
      name: "replace",
      placeholder: "Replace",
      value: q.replace,
    })

    this.caseBtn = helmMatchOption("Aa", "Match Case", q.caseSensitive)
    this.wordBtn = helmMatchOption("W", "Match Whole Word", q.wholeWord)
    this.reBtn = helmMatchOption(".*", "Use Regular Expression", q.regexp)

    const commit = () => this.commit()
    this.searchField.addEventListener("input", commit)
    this.replaceField.addEventListener("input", commit)
    for (const btn of [this.caseBtn, this.wordBtn, this.reBtn]) {
      btn.addEventListener("helm-toggle", commit)
    }

    this.expandBtn = el("button", {
      type: "button",
      className: "helm-search-expand",
      title: "Toggle Replace",
      "aria-label": "Toggle Replace",
      "aria-expanded": "false",
    })
    this.expandBtn.addEventListener("click", (e) => {
      e.preventDefault()
      this.setReplaceExpanded(!this.replaceExpanded)
    })
    if (view.state.readOnly) {
      this.expandBtn.disabled = true
      this.expandBtn.title = "Replace unavailable (read-only)"
    }

    const findRow = el("div", { className: "helm-search-row helm-search-row-find" }, [
      helmFieldWrap(this.searchField, [this.caseBtn, this.wordBtn, this.reBtn]),
      el("div", { className: "helm-search-trailing" }, [
        el("div", { className: "helm-search-actions helm-search-actions-icons" }, [
          helmSearchButton({
            label: "↑",
            title: "Previous Match",
            onClick: () => findPrevious(view),
          }),
          helmSearchButton({
            label: "↓",
            title: "Next Match",
            onClick: () => findNext(view),
          }),
          helmSearchButton({
            label: "✕",
            title: "Close",
            className: "helm-search-btn helm-search-close",
            onClick: () => closeSearchPanel(view),
          }),
        ]),
      ]),
    ])

    this.replaceRow = el("div", { className: "helm-search-row helm-search-row-replace" }, [
      helmFieldWrap(this.replaceField),
      el("div", { className: "helm-search-trailing" }, [
        el("div", { className: "helm-search-actions" }, [
          helmSearchButton({
            label: "Replace",
            title: "Replace",
            className: "helm-search-btn helm-search-btn-text",
            onClick: () => {
              this.commit()
              replaceNext(view)
            },
          }),
          helmSearchButton({
            label: "All",
            title: "Replace All",
            className: "helm-search-btn helm-search-btn-text",
            onClick: () => {
              this.commit()
              replaceAll(view)
            },
          }),
        ]),
      ]),
    ])

    this.dom = el("div", { className: "cm-search helm-search", role: "search" }, [
      this.expandBtn,
      el("div", { className: "helm-search-body" }, [findRow, this.replaceRow]),
    ])
    this.dom.addEventListener("keydown", (e) => this.onKeyDown(e))
    this.applyReplaceExpanded()
  }

  get top() {
    return true
  }

  mount() {
    this.searchField.select()
  }

  setReplaceExpanded(on) {
    if (this.view.state.readOnly) return
    this.replaceExpanded = !!on
    this.applyReplaceExpanded()
    if (this.replaceExpanded) {
      requestAnimationFrame(() => {
        this.replaceField.focus()
        this.replaceField.select()
      })
    }
  }

  applyReplaceExpanded() {
    syncReplaceOpenDOM(this.dom, this.replaceExpanded && !this.view.state.readOnly)
  }

  commit() {
    const query = new SearchQuery({
      search: this.searchField.value,
      replace: this.replaceField.value,
      caseSensitive: isMatchOptionOn(this.caseBtn),
      wholeWord: isMatchOptionOn(this.wordBtn),
      regexp: isMatchOptionOn(this.reBtn),
    })
    if (!query.eq(getSearchQuery(this.view.state))) {
      this.view.dispatch({ effects: setSearchQuery.of(query) })
    }
  }

  onKeyDown(e) {
    if (e.key === "Escape") {
      e.preventDefault()
      closeSearchPanel(this.view)
      return
    }
    if ((e.metaKey || e.ctrlKey) && e.altKey && (e.key === "f" || e.key === "F")) {
      e.preventDefault()
      this.setReplaceExpanded(true)
      return
    }
    if (e.key === "Enter" && e.target === this.searchField) {
      e.preventDefault()
      this.commit()
      ;(e.shiftKey ? findPrevious : findNext)(this.view)
      return
    }
    if (e.key === "Enter" && e.target === this.replaceField) {
      e.preventDefault()
      this.commit()
      replaceNext(this.view)
    }
  }

  update(update) {
    for (const tr of update.transactions) {
      for (const effect of tr.effects) {
        if (effect.is(setSearchQuery)) this.syncFromQuery(effect.value)
      }
    }
  }

  syncFromQuery(query) {
    if (this.searchField.value !== query.search) this.searchField.value = query.search
    if (this.replaceField.value !== query.replace) this.replaceField.value = query.replace
    setMatchOptionPressed(this.caseBtn, query.caseSensitive)
    setMatchOptionPressed(this.wordBtn, query.wholeWord)
    setMatchOptionPressed(this.reBtn, query.regexp)
  }
}

/** Open find panel; `withReplace` expands Replace like VS Code ⌘⌥F. */
function openFindPanel(view, withReplace = false) {
  const wantReplace = !!withReplace && !view.state.readOnly
  pendingOpenWithReplace = wantReplace
  const ok = openSearchPanel(view)
  const apply = () => {
    const panel = view.dom.querySelector(".helm-search")
    syncReplaceOpenDOM(panel, wantReplace)
    focusPanelField(panel, wantReplace)
  }
  apply()
  requestAnimationFrame(apply)
  return ok
}

/**
 * Desktop-IDE-style bindings on top of CM defaults.
 * Zoom / find use preventDefault so the host doesn’t steal Mod keys.
 * Note: on iPad, ⌘F often never reaches JS — Swift UIKeyCommand also calls runCommand("find").
 */
function helmEditorKeymap() {
  return keymap.of([
    // Font size (VS Code / Xcode style)
    { key: "Mod-=", run: (v) => bumpFontSize(v, 1), preventDefault: true },
    { key: "Mod-+", run: (v) => bumpFontSize(v, 1), preventDefault: true },
    { key: "Mod--", run: (v) => bumpFontSize(v, -1), preventDefault: true },
    { key: "Mod-_", run: (v) => bumpFontSize(v, -1), preventDefault: true },
    { key: "Mod-0", run: (v) => setFontSize(v, FONT_DEFAULT), preventDefault: true },

    // Line bookmark (Xcode-style navigator)
    { key: "Mod-F2", run: toggleBookmarkAtCursor, preventDefault: true },
    { key: "Mod-Alt-b", run: toggleBookmarkAtCursor, preventDefault: true },

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

    // Save (⌘S) — host writes via vfs/write
    {
      key: "Mod-s",
      run: () => postSaveRequest(),
      preventDefault: true,
      stopPropagation: true,
    },

    // Find widget (⌘F find-only; ⌘⌥F expand replace) — VS Code parity.
    {
      key: "Mod-f",
      run: (v) => openFindPanel(v, false),
      preventDefault: true,
      stopPropagation: true,
    },
    {
      key: "Mod-Alt-f",
      run: (v) => openFindPanel(v, true),
      preventDefault: true,
      stopPropagation: true,
    },
    { key: "Mod-g", run: findNext, preventDefault: true },
    { key: "Shift-Mod-g", run: findPrevious, preventDefault: true },
    {
      key: "Escape",
      run: (v) => closeSearchPanel(v) || simplifySelection(v),
      preventDefault: true,
    },
  ])
}

/**
 * Capture-phase fallback when key events reach the document but not CM’s keymap
 * (still won’t help if UIKit never delivers ⌘F — that’s the Swift UIKeyCommand path).
 */
function installFindKeyCapture() {
  window.addEventListener(
    "keydown",
    (event) => {
      if (!view) return
      const mod = event.metaKey || event.ctrlKey
      if (!mod) return
      const key = (event.key || "").toLowerCase()
      if (key === "s") {
        event.preventDefault()
        event.stopPropagation()
        postSaveRequest()
      } else if (key === "f") {
        event.preventDefault()
        event.stopPropagation()
        openFindPanel(view, event.altKey)
      } else if (key === "g" && event.shiftKey) {
        event.preventDefault()
        findPrevious(view)
      } else if (key === "g") {
        event.preventDefault()
        findNext(view)
      }
    },
    true,
  )
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

function makeExtensions({ language, dark, readOnly, merge, original }) {
  const isMerge = !!merge
  const exts = [
    lineNumbers(),
    // Bookmarks are editor-only; skip in merge/diff surface.
    ...(isMerge ? [] : [bookmarkField, bookmarkGutter()]),
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
    // IDE-style find/replace docked to the top of the editor (⌘F).
    search({
      top: true,
      createPanel: (v) => new HelmSearchPanel(v),
    }),
    EditorView.lineWrapping,
    ...(isMerge ? [] : [documentChangeExtension()]),
    cursorPositionExtension(),
    editorKeymap(),
    // Higher precedence than defaults so zoom / IDE keys win when overlapping.
    helmEditorKeymap(),
    baseTheme(dark),
    // Font size compartment before oneDark (layout-only theme).
    fontSizeCompartment.of(fontSizeTheme(fontSizePx)),
  ]

  if (isMerge) {
    exts.push(
      unifiedMergeView({
        original: typeof original === "string" ? original : "",
        mergeControls: false,
        highlightChanges: true,
        gutter: true,
        collapseUnchanged: { margin: 2, minSize: 4 },
      }),
    )
  }

  // oneDark must be the last CM *color* theme.
  if (dark) {
    exts.push(oneDark)
  }

  if (readOnly || isMerge) {
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

  /** Last bookmark lines from host; re-applied after setDocument rebuilds state. */
  let lastBookmarkLines = []

  window.HelmCodeEditor = {
    setDocument({ text, language, dark, readOnly, bookmarks, merge, original }) {
      if (!view) return
      const isDark = !!dark
      const isMerge = !!merge
      setShellScheme(isDark)
      if (Array.isArray(bookmarks)) {
        lastBookmarkLines = bookmarks
      }
      view.setState(
        EditorState.create({
          doc: typeof text === "string" ? text : "",
          extensions: makeExtensions({
            language: language || "plain",
            dark: isDark,
            readOnly: !!readOnly || isMerge,
            merge: isMerge,
            original: typeof original === "string" ? original : "",
          }),
        }),
      )
      if (!isMerge) {
        applyBookmarkLines(view, lastBookmarkLines)
      }
      postCursorPosition(view)
      requestAnimationFrame(() => view.requestMeasure())
    },
    /**
     * Hot-reload body only: soft replace + keep the previous top-of-viewport line.
     * Prefer this over setDocument for remote didChange updates.
     */
    replaceDocumentText(text, opts) {
      replaceDocumentText(text, opts || { preserveTopLine: true })
      if (view && lastBookmarkLines.length) {
        applyBookmarkLines(view, lastBookmarkLines)
      }
    },
    /**
     * Append text at end of document (chunked VFS stream load).
     * Does not rebuild state; call setDocument first with "" for a new stream.
     */
    appendDocumentText(text) {
      if (!view) return
      const t = typeof text === "string" ? text : ""
      if (!t) return
      const len = view.state.doc.length
      view.dispatch({
        changes: { from: len, to: len, insert: t },
        // Avoid scroll jump while streaming.
        userEvent: "input.paste",
      })
    },
    firstVisibleLine() {
      return view ? firstVisibleLineNumber(view) : 1
    },
    setBookmarks(lines) {
      if (!view) return
      lastBookmarkLines = Array.isArray(lines) ? lines : []
      applyBookmarkLines(view, lastBookmarkLines)
    },
    goToLine(line) {
      if (!view) return
      goToLine(view, line)
      postCursorPosition(view)
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
    /**
     * Run a named command from the host (system edit-menu custom actions).
     * Returns true when the command was applied.
     */
    runCommand(name) {
      if (!view) return false
      switch (String(name || "")) {
        case "toggleComment":
          return !!toggleComment(view)
        case "toggleBookmark":
          return !!toggleBookmarkAtCursor(view)
        case "selectLine":
          return !!selectLine(view)
        case "find":
          return !!openFindPanel(view, false)
        case "findReplace":
          return !!openFindPanel(view, true)
        case "findNext":
          return !!findNext(view)
        case "findPrevious":
          return !!findPrevious(view)
        case "indentMore":
          return !!indentMore(view)
        case "indentLess":
          return !!indentLess(view)
        case "deleteLine":
          return !!deleteLine(view)
        case "save":
          return !!postSaveRequest()
        default:
          return false
      }
    },
  }

  installFindKeyCapture()

  try {
    window.webkit?.messageHandlers?.helmEditor?.postMessage({ type: "ready" })
  } catch (_) {}
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot)
} else {
  boot()
}
