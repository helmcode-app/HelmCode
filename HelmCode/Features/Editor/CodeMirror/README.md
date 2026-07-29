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

## Rebuild

From the repo root (Node 20+):

```bash
./scripts/rebuild-codemirror.sh
```

Then rebuild the Xcode target so assets are copied into the app bundle.
