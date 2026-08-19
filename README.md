# HelmCode

Mobile-first iPad AI coding console — pure SwiftUI shell with a **CodeMirror 6** editor host, connected to **runner-core** (`open-core` HTTP API).

## Architecture

```
HelmCode/
├── App/                      # @main, RootView, WorkspaceRuntimeModifier
├── Core/
│   ├── Models/
│   │   ├── API/              # sessions wire + Agent / composer models
│   │   └── Workspace/        # tree, search, SCM, language hints
│   ├── Network/
│   │   ├── …                 # HTTP client, RunnerURL, BackendConnectionSync
│   │   ├── Agent/            # /v1/sessions REST + history poll
│   │   └── VFS/              # /v1/vfs WebSocket transport + stream
│   ├── Preferences/          # AppStorage keys, layout metrics
│   └── Session/              # WorkspaceSession (+ Persistence / Tree / VFS / …)
├── Features/
│   ├── Sidebar/              # Projects · navigators · Settings bar
│   ├── Editor/
│   │   ├── Welcome/          # start page, Open Project, project settings
│   │   ├── CodeMirror/       # CM6 host (Swift + offline web assets)
│   │   ├── Terminal/         # WebSSH xterm.js full-column panel (⌘J)
│   │   └── Editor*.swift     # detail routing, canvas, empty, switcher
│   ├── Commander/            # AgentCommandPanel + timeline + `/` `@` composer
│   └── Settings/             # appearance / layout / shortcuts
└── Shared/UI/                # chrome, search field, avatars, file type icons
```

| Layer | Responsibility |
|-------|----------------|
| **App** | DI, NavigationSplitView + inspector chrome, settings sheet |
| **Core** | Domain models, network transport, prefs, session state |
| **Features** | UI by product column (Sidebar / Editor / Commander / Settings) |
| **Shared** | Cross-feature controls only (no business logic) |

**Settings:** Appearance (titleless inline theme) · Layout · About (shortcuts + `AppBundleInfo`).  
Sheets share `helmSheetCloseToolbar` / `helmInlineNavigationTitle`.  
Column empty states: `FeatureEmptyPlaceholder` (icon) vs `SidebarEmptyPlaceholder` (text).

**Dependency direction:** `App → Features → Core`, `Features → Shared`. Network does not own session; `WorkspaceSession` applies VFS trees.

### Shell layout

| Column | Mechanism |
|--------|-----------|
| Sidebar (leading) | `NavigationSplitView` system sidebar |
| Editor (center) | Detail: welcome → empty project → CodeMirror **or** full-column Terminal (⌘J) |
| Commander (trailing) | System `.inspector` column |

### Editor detail surfaces

| State | View | Leading toolbar |
|-------|------|-----------------|
| No project open | `EditorWelcomeView` | Welcome |
| Project open, no file | `EditorEmptyStateView` | Project switcher |
| File selected | `EditorCanvasView` | Project switcher + file name |
| Terminal mode (⌘J) | `TerminalPanelView` (project-scoped WebSSH) | Same; toggle icon gray without project |

**Terminal session:** kept alive across ⌘J hide/show; wiped on project switch/close or shell `exit`.  
Details: `Features/Editor/Terminal/WebSSH.md`.

**Welcome → Open Project:** Hosted (placeholder) | Self-hosted URL (`OpenProjectSheet`).  
Projects are **only** added via Open Project (no seed mocks). Metadata is cached in `UserDefaults`; trees reload from VFS on open.  
**Recent:** up to 5 rows; **More…** opens `BrowseProjectsSheet` when there are more.

### Sidebar

| State | Content |
|-------|---------|
| No project | **Projects** list (row-trailing runner reachability icons) |
| Project open | System segmented **navigator**: Files · Search · Bookmarks · Source Control |
| Project open | Top trailing: global **VFS status** + system **sidebarToggle** |
| Always | Bottom **Settings** via system `safeAreaBar` + soft scroll-edge fade |

- **Files** — keyboard outline (`SidebarFileTreeModel` / `SidebarFileTreeKeyboard`): ←/→ expand, ↑/↓ move + auto-scroll  
- **Search** — find in project (case / whole-word); open match jumps to line  
- **Bookmarks** — file/folder marks + editor line marks; type icons in the list  
- **Source Control** — `Features/SourceControl/` (sidebar + center Diff); runner `vfs/gitStatus` / `gitRefs` / `gitShow` / `gitCheckout`; commit/sync via Terminal or Agent  
- File type icons: Devicon **1x/2x/3x PNG** in `Assets.xcassets/FileTypeIcons/`  
  · resolve: `FileLanguageHint` (+ BrandAssets / ResolveTables)  
  · UI: `FileTypeIcon` · tints: `WorkspaceNodeIconStyle`  
  · monochrome logos (Markdown, Rust, …) render as **template** for dark mode  
  · SF Symbols when no brand asset  
- Project avatars (IDEA-style): `ProjectAvatarStyle` + `ProjectAvatarIcon` / `ProjectAvatarImage`  
  · initials on glyph only; toolbar Menu uses raster image + full name  
- Shared chrome: `SidebarChrome` (`helmSidebarListStyle`, `SidebarSettingsBar`, `SidebarVFSStatusIcon`)  
- Per-project API probe: `ProjectRunnerStatusMonitor` (list trailing only; not the top VFS glyph)  
- Project switching lives in the **center toolbar** (not the sidebar)

### VFS (remote workspace)

Connects to runner-core **JSON-RPC over WebSocket** (`docs/api/vfs.md` in `runner-core`):

| Item | Value |
|------|--------|
| Endpoint | `ws(s)://<host>/v1/vfs` (from Backend base URL) |
| Auth | Same Bearer token as open-core when configured |
| Client | `VFSNetworkEngine` — heartbeat, auto-reconnect, request/response map |
| Methods | `vfs/initialize`, `vfs/read`, `vfs/read_chunk`, `vfs/write`, `vfs/shutdown`, git (`gitStatus` / `gitRefs` / `gitDiff` / `gitShow` / `gitCheckout`) |
| Stream | `VFSStreamEngine` progressive open for large files |
| Notifications | `vfs/didChange` → selective buffer reload / tree refresh (non-blocking receive) |
| Editor | Autosave + ⌘S write-back; soft hot-reload keeps open file + scroll |
| Identity | `initialize.name` / `remote` / `branch` → project title / subtitle / SCM |
| Persistence | `SavedProjectRecord` in UserDefaults (metadata only; tree reloaded via VFS) |
| Bridge | `WorkspaceRuntimeBridge` (+ `+SourceControl`) binds engines ↔ `WorkspaceSession` |
| Git client | `VFSGitModels` · `VFSNetworkEngine+Git` |
| URL helpers | `RunnerURL` · `VFSPath` · `VFSConnect` (Open Project self-hosted flow) |

Flat `entries` from initialize are assembled client-side into `WorkspaceNode` (`WorkspaceTreeAssembler`).

## Backend

Default: `http://127.0.0.1:18080` (Docker host port → container `8080`; see runner-core `compose.dev.yaml`).

| Route | Role |
|-------|------|
| `GET /health` | Mode + liveness |
| `GET /v1/status` | Runtime snapshot |
| `GET /v1/workspaces` | Workspace catalog (`default` = primary repo) |
| `*` `/v1/sessions/*` | **Agent command panel** — REST + SSE |
| `WS /v1/vfs` | Workspace tree / chunked read / write (`?workspaceId=`) |
| `WS /v1/terminal` | **WebSSH** — xterm.js PTY (`?workspaceId=`) |

### Agent Commander

| Component | Role |
|-----------|------|
| `AgentCommandPanel` | Shell: header + timeline + composer dock |
| `AgentCommandComposer` | Prompt chrome: branch / usage / mode / model / send |
| `AgentComposerTriggerDock` | `/` skills + `@` files (in-chat picker, not a system sheet) |
| `AgentTimelineView` | Session scroll list (`EventLog`) |
| `AgentNetworkEngine` | `/v1/sessions` client (create / prompt / history / cancel / rewind) |
| `HelmCodeNetworkEngine` | `GET /health` + `GET /v1/status` probe only |

Optional Bearer (`OPENCORE_API_TOKEN`): enter when **Open Project → Self-hosted** (stored for reopens; not a separate Settings backend).

## CodeMirror 6

Rebuild the offline editor bundle:

```bash
./scripts/rebuild-codemirror.sh
```

Theme constraints (see `Features/Editor/CodeMirror/README.md`):

- CM themes: `baseTheme` then `oneDark` only — nothing after `oneDark`
- Dark caret-row highlight: `data-helm-scheme` + CSS in `index.html`
- Font size via `Compartment`; shortcuts listed in Settings → About
- Languages: `FileLanguageHint` → `CodeMirrorLanguage` → `editor-entry.mjs` `languageExtension`
  (Swift/TS/JS/HTML/CSS/Go/Python/Rust/Java/YAML/SQL/Dockerfile/Shell/…)

## Build

Open `HelmCode.xcodeproj` in Xcode (iPad destination recommended).

```bash
xcodebuild -project HelmCode.xcodeproj -target HelmCode \
  -sdk iphonesimulator -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

## License

See [LICENSE](./LICENSE).
