# Tech Stack

## Swift app

- Swift 5 language mode, macOS 14+ deployment target, built with Xcode 26+ (newer SDK enables Liquid Glass on macOS 26+)
- Swift Observation (`@Observable`) — NOT `ObservableObject`
- Project: `KhVolume/KhVolume.xcodeproj` (targets `KhVolume` app, `KhVolumeTests` hosted unit tests). Do not build with SwiftPM: `swift build` records the deployment target as the SDK version, which disables the current system design
- Dependencies (Swift packages added in the Xcode project):
  - `KeyboardShortcuts` ≥ 2.0 (sindresorhus/KeyboardShortcuts) — global hotkeys
  - `Network` framework (linked explicitly via `linkerSettings`)

## Python helper

- Python 3.10 (pinned via `mise.toml`)
- Package manager: `uv` (latest via mise)
- Runtime deps: `zeroconf==0.148.0`, `pyssc @ git+https://github.com/schwinn/pyssc.git@main`
- Build-only dep: `PyInstaller==6.14.1`
- Source: `KhVolume/Helper/khvol_cli.py` + `KhVolume/Helper/pyproject.toml`

## Build tooling

- `mise` for Python/uv version management (`mise.toml` at repo root)
- PyInstaller bundles helper into `KhVolume/Helpers/khvol-bundle/` (onedir); the Release build copies it to `Contents/Resources/khvol-bundle/` in the app
- Shell scripts in `scripts/`: `build-khvol-helper.sh`, `build-app-bundle.sh`, `sign-app.sh`, `smoke-test.sh`
