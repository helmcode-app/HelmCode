# WebSSH Terminal (xterm.js)

Full-column surface in the editor detail (exclusive with CodeMirror) — toggle with **⌘J**.

## Module layout

| File | Role |
|------|------|
| `TerminalPanelView` | Chrome bar, reconnect / hide |
| `TerminalHostView` | `UIViewRepresentable` shell |
| `TerminalHostCoordinator` | WK bridge + connect state machine |
| `TerminalWebContainer` | UIKit container; size → FitAddon |
| `TerminalBundle` | Asset paths + JS snippets |
| `TerminalLinkStatus` | ok / err / info for chrome |
| `TerminalEndpoint` | Resolve project / engine base URL |
| `TerminalVisibilityStore` | ⌘J visibility; avoids stale `@AppStorage` after exit |
| `terminal.html` + `terminal.bundle.js` | Offline xterm client |

## Session policy

| Rule | Behavior |
|------|----------|
| No open project | Terminal toggle disabled (gray) |
| ⌘J hide / show | **Keeps** WebSocket + scrollback (panel mounted, opacity only) |
| `exit` in shell | Ends PTY, clears history, returns to editor, bumps session epoch |
| Switch / close project | Bumps epoch → wipe + disconnect; leave Terminal mode |
| Connect dedupe | `lastAttemptToken` prevents thrashing `connect()` on every `updateUIView` |
| Exit race | Keep attempt token on `sessionEnded` until epoch bumps; persist hide via `TerminalVisibilityStore` before next ⌘J |

## Wire protocol

See `runner-core/docs/api/terminal.md`:

| Item | Value |
|------|--------|
| Endpoint | `ws(s)://<runner>/v1/terminal?cols=&rows=&ticket=&workspaceId=` |
| Binary frames | PTY stdin / stdout |
| Text JSON | `resize` · `ping` / `pong` · `ready` · `error` · `exit` |

Control JSON is never written to the PTY surface. `@xterm/addon-attach` is not used (mixed framing).

## Resize (iPad)

1. `FitAddon.fit()` measures `#terminal` → `cols` / `rows`
2. Listeners: window / visualViewport / ResizeObserver + Swift bounds
3. Client sends `{ type: "resize", cols, rows }`

## Rebuild

```bash
./scripts/rebuild-terminal.sh
```
