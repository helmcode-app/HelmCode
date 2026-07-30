# CodeMirror 6 host

Offline assets for `CodeMirrorHostView`.

| File | Role |
|------|------|
| `index.html` | Shell page + dark active-line CSS |
| `editor.bundle.js` | Minified CM6 IIFE → `window.HelmCodeEditor` |
| `editor-entry.mjs` | Source used to rebuild the bundle |

## Invariants (do not regress)

1. **Theme order:** `baseTheme` (layout) → `oneDark` (dark only). Do **not** mount another `EditorView.theme` after `oneDark` — that has wiped text colors in WKWebView.
2. **Dark active line:** set `document.documentElement.dataset.helmScheme` and style `.cm-activeLine` / `.cm-activeLineGutter` in `index.html`. CM does not expose a stable `.cm-dark` class.
3. Soft-wrap is always on (`EditorView.lineWrapping` + CSS).
4. **Font size** lives in a `Compartment` (before `oneDark`), not a post-oneDark theme.

## Keyboard shortcuts

In-app reference: **Settings → About → Keyboard Shortcuts**  
(`EditorKeyboardShortcuts.swift` — keep in sync with `helmEditorKeymap` in `editor-entry.mjs`).

Core bindings (editor focused): font zoom `⌘+/-/0`, undo/redo, find, comment, indent, move/delete line, fold, etc. Plus CodeMirror defaults.

**Find (`⌘F`):** VS Code–style floating widget — **fixed width, top-right**, find-only by default. Left **▶/▼** expands Replace. `⌘⌥F` opens with replace expanded. Search state uses CM `SearchQuery`; chrome is `HelmSearchPanel` + `.helm-search` CSS.

On iPad, `CodeMirrorWebView` uses `UIKeyCommand` + `wantsPriorityOverSystemBehavior` so `⌘F` reaches the editor. Esc closes; `⌘G` / `⌘⇧G` find next/previous.

**Line bookmarks (Xcode-style):** `⌘ F2` / `⌘ ⌥ B` toggles the caret line; click the bookmark gutter to toggle that line. Host APIs: `setBookmarks([line…])`, `goToLine(n)`. Markers are filled bookmark SVG icons (color in `index.html`, not a CM color theme).

## System context menu (custom entries)

`CodeMirrorWebView` keeps the **system** edit/context menu and appends:

| Action | Command id |
|--------|------------|
| Toggle Comment | `toggleComment` |
| Toggle Bookmark | `toggleBookmark` |
| Select Line | `selectLine` |
| Find | `find` |

Implemented only via `buildMenu(with:)` on `CodeMirrorWebView` (no `UIMenuItem` — that duplicated entries under Share). Menu specs live in `CodeMirrorCommand.contextMenuItems`; actions call `HelmCodeEditor.runCommand(...)`.

## Rebuild

From the repo root (Node 20+):

```bash
./scripts/rebuild-codemirror.sh
```

Then rebuild the Xcode target so assets are copied into the app bundle.
