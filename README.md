# HelmCode

Mobile-first iPad AI coding console — pure SwiftUI shell with a **CodeMirror 6** editor host, connected to **runner-core** (`open-core` HTTP API).

## Architecture

```
HelmCode/
├── App/                 # @main, RootView (NavigationSplitView + .inspector)
├── Core/
│   ├── Models/          # API + workspace domain types
│   ├── Network/         # RunnerCoreAPIClient + HelmCodeNetworkEngine
│   ├── Preferences/     # AppStorage keys, layout metrics, appearance
│   └── Session/         # WorkspaceSession (project / file / recents)
├── Features/
│   ├── Sidebar/         # Projects · navigator tabs (Files / Bookmarks / SCM)
│   ├── Editor/          # Welcome · empty project · CodeMirror canvas
│   ├── Commander/       # System inspector: task prompt + timeline
│   └── Settings/        # Appearance / layout / backend / shortcuts
├── Shared/UI/           # Toolbar labels, inset cards, status dot, inspector toggle
└── …/CodeMirror/        # index.html + editor.bundle.js (offline CM6)
```

| Layer | Responsibility |
|-------|----------------|
| **App** | DI, NavigationSplitView + inspector chrome, settings sheet |
| **Core** | Domain models, HTTP, prefs, session state |
| **Features** | UI surfaces by product area |
| **Shared** | Cross-feature controls |

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

### Sidebar

| State | Content |
|-------|---------|
| No project | **Projects** list |
| Project open | System segmented **navigator**: Files · Bookmarks · Source Control |

- **Files** — outline tree; create / rename / delete / bookmark via context menu  
- **Bookmarks** — saved nodes; empty state is text-only, centered  
- **Source Control** — local mock (stage / commit / pull·push·fetch)  
- Project switching lives in the **center toolbar** (not the sidebar)

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

## Build

Open `HelmCode.xcodeproj` in Xcode (iPad destination recommended).

```bash
xcodebuild -project HelmCode.xcodeproj -target HelmCode \
  -sdk iphonesimulator -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

## License

See [LICENSE](./LICENSE).
