# WebSSH Terminal (xterm.js)

Full-column surface in the editor detail (exclusive with CodeMirror) — toggle with **⌘J**.

## Wire protocol

See `runner-core/docs/api/terminal.md`:

| Item | Value |
|------|--------|
| Endpoint | `ws(s)://<runner>/v1/terminal?cols=&rows=&token=` |
| Binary frames | PTY stdin / stdout |
| Text JSON | `{ type: "resize", cols, rows }` · `ping` / `pong` · `ready` · `error` · `exit` |

`@xterm/addon-attach` is **not** used: the server mixes binary PTY data with JSON control frames. Attach is implemented manually in `terminal-entry.mjs`. Control JSON is never written to the PTY surface.

## Resize (iPad keyboard / rotation)

1. `FitAddon.fit()` measures the `#terminal` DOM box (points → cell grid).
2. Listeners: `window.resize`, `orientationchange`, `visualViewport`, `ResizeObserver`, plus Swift `TerminalWebContainer` bounds.
3. After fit, client sends `{ type: "resize", cols: term.cols, rows: term.rows }`.

## Rebuild bundle

```bash
./scripts/rebuild-terminal.sh
```

Writes offline `terminal.bundle.js` (`@xterm/xterm` + fit + web-links + CSS).

## Swift surface

| Type | Role |
|------|------|
| `TerminalPanelView` | Chrome bar, reconnect / back to editor |
| `TerminalHostView` | WKWebView bridge + connection state machine |
| `TerminalWebContainer` | UIKit container; reports size changes |
| `TerminalBundle` | Asset paths + JS snippets |
| `TerminalLinkStatus` | ok / err / info for chrome status |
