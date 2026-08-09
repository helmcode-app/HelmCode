# HelmCode App Icon — Icon Composer (`.icon`)

## Source of truth

| Path | Notes |
|------|--------|
| `HelmCode/AppIcon.icon/` | **Active** Icon Composer package used by Xcode |
| `HelmCode/AppIcon.icon/icon.json` | Layers, fill, shadow, translucency |
| `HelmCode/AppIcon.icon/Assets/` | Layer PNGs (e.g. `1 4.png`) |

Build setting: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`  
(matches the package name `AppIcon.icon`).

## Edit / replace

1. Open or export from **Icon Composer** → save as `AppIcon.icon`
2. Replace `HelmCode/AppIcon.icon` (folder package)
3. Clean + Run — iOS applies the system mask (do **not** bake rounded corners into the art)

## Legacy

Older PNG masters under `Design/AppIcon/` (`background.png`, `foreground.png`, `app_icon_square.png`) are reference only.  
`Assets.xcassets/AppIcon.appiconset` was removed in favor of the `.icon` package.
