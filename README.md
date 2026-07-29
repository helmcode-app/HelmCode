# HelmCode

Mobile-first, premium iPad AI coding console — pure SwiftUI shell with a **CodeMirror 6** editor host, connected to **runner-core** (`open-core` HTTP API).

## Architecture

```
HelmCode/
├── App/                 # @main, RootView (NavigationSplitView shell)
├── Core/
│   ├── Models/          # API + workspace domain types
│   ├── Network/         # RunnerCoreAPIClient + HelmCodeNetworkEngine
│   ├── Preferences/     # AppStorage keys, layout metrics, appearance
│   └── Session/         # WorkspaceSession (project / file selection)
├── Features/
│   ├── Sidebar/         # System sidebar list + Settings entry
│   ├── Editor/          # CodeMirror 6 WKWebView host
│   ├── Commander/       # Task prompt + event timeline
│   ├── Settings/        # Appearance / layout / backend
│   └── Shell/           # Detail canvas (editor + inspector)
├── Shared/UI/           # Resize handle, toolbar labels, toggles
└── …/CodeMirror/        # index.html + editor.bundle.js (offline CM6)
```

| Layer | Responsibility |
|-------|----------------|
| **App** | DI, split-view chrome, settings sheet |
| **Core** | Domain models, HTTP, prefs, session state |
| **Features** | UI surfaces by product area |
| **Shared** | Cross-feature controls |

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

## Build

Open `HelmCode.xcodeproj` in Xcode (iPad destination recommended).

```bash
xcodebuild -project HelmCode.xcodeproj -target HelmCode \
  -sdk iphonesimulator -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

## License

See [LICENSE](./LICENSE).
