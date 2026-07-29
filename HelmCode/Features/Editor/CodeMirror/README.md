# CodeMirror 6 host

Offline assets for `CodeMirrorHostView`.

| File | Role |
|------|------|
| `index.html` | Shell page |
| `editor.bundle.js` | Minified CM6 IIFE → `window.HelmCodeEditor` |
| `editor-entry.mjs` | Source used to rebuild the bundle |

## Rebuild

From the repo root (Node 20+):

```bash
./scripts/rebuild-codemirror.sh
```

Then rebuild the Xcode target so the new JS is copied into the app bundle.
