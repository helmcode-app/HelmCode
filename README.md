# HelmCode

Mobile-first iPad AI coding console — pure SwiftUI shell with a **CodeMirror 6** editor host, connected to **runner-core** (`open-core` HTTP API).

## Architecture

```
HelmCode/
├── App/                      # @main, RootView shell
├── Core/
│   ├── Models/
│   │   ├── API/              # open-core Codable types
│   │   └── Workspace/        # tree, search, SCM models, VFS tree assembler
│   ├── Network/
│   │   ├── …                 # HTTP task client, RunnerURL, connection sync
│   │   └── VFS/              # WebSocket JSON-RPC transport only
│   ├── Preferences/          # AppStorage keys, layout metrics
│   └── Session/              # WorkspaceSession (+ Tree / Bookmarks / SCM / VFS)
├── Features/
│   ├── Sidebar/              # Projects · navigators · Settings bar
│   ├── Editor/
│   │   ├── Welcome/          # start page, Open Project, Browse Projects
│   │   ├── CodeMirror/       # CM6 host (Swift + offline web assets)
│   │   └── Editor*.swift     # detail routing, canvas, empty, switcher
│   ├── Commander/            # inspector: prompt + timeline
│   └── Settings/             # appearance / layout / backend / shortcuts link
└── Shared/UI/                # system chrome, search field, cards, toggles
```

| Layer | Responsibility |
|-------|----------------|
| **App** | DI, NavigationSplitView + inspector chrome, settings sheet |
| **Core** | Domain models, network transport, prefs, session state |
| **Features** | UI by product column (Sidebar / Editor / Commander / Settings) |
| **Shared** | Cross-feature controls only (no business logic) |

**Dependency direction:** `App → Features → Core`, `Features → Shared`. Network does not own session; `WorkspaceSession` applies VFS trees.

### Shell layout

| Column | Mechanism |
|--------|-----------|
| Sidebar (leading) | `NavigationSplitView` system sidebar |
| Editor (center) | Detail: welcome → empty project → CodeMirror |
| Commander (trailing) | System `.inspector` column |

### Editor detail surfaces

| State | View | Leading toolbar |
|-------|------|-----------------|
| No project open | `EditorWelcomeView` | Welcome |
| Project open, no file | `EditorEmptyStateView` | Project switcher |
| File selected | `EditorCanvasView` | Project switcher + file name |

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
- **Source Control** — local mock (stage / commit / pull·push·fetch)  
- File type icons: Devicon **1x/2x/3x PNG** in `Assets.xcassets/FileTypeIcons/`  
  · resolve: `FileLanguageHint` (+ BrandAssets / ResolveTables)  
  · UI: `FileTypeIcon` · tints: `WorkspaceNodeIconStyle`  
  · monochrome logos (Markdown, Rust, …) render as **template** for dark mode  
  · SF Symbols when no brand asset  
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
| Methods | `vfs/initialize`, `vfs/read`, `vfs/read_chunk`, `vfs/write`, `vfs/shutdown` |
| Stream | `VFSStreamEngine` progressive open for large files |
| Notifications | `vfs/didChange` → selective buffer reload / tree refresh (non-blocking receive) |
| Editor | Autosave + ⌘S write-back; soft hot-reload keeps open file + scroll |
| Identity | `initialize.name` / `remote` / `branch` → project title / subtitle / SCM |
| Persistence | `SavedProjectRecord` in UserDefaults (metadata only; tree reloaded via VFS) |
| Bridge | `WorkspaceRuntimeBridge` binds engines ↔ `WorkspaceSession` |
| URL helpers | `RunnerURL` · `VFSPath` · `VFSConnect` (Open Project self-hosted flow) |

Flat `entries` from initialize are assembled client-side into `WorkspaceNode` (`WorkspaceTreeAssembler`).

## Backend

Default: `http://127.0.0.1:8080` (runner-core open-core).

| Route | Role |
|-------|------|
| `GET /health` | Mode + liveness |
| `GET /v1/status` | Runtime snapshot |
| `POST /v1/tasks` | Async submit → `202` |
| `GET /v1/tasks/:id` | Poll status / events / result |
| `POST /v1/tasks/:id/cancel` | Cancel |

Optional: `Authorization: Bearer <OPENCORE_API_TOKEN>` in **Settings → Backend**.

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
