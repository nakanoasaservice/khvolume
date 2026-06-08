# Tech Stack

## Swift app

- Swift 5.9+ (`swift-tools-version: 5.9`), macOS 14+ target
- Swift Observation (`@Observable`) — NOT `ObservableObject`
- Package: `KhVolume/Package.swift`
- Dependencies:
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
- PyInstaller bundles helper into `KhVolume/Helpers/khvol-bundle/` (onedir)
- Shell scripts in `scripts/`: `build-khvol-helper.sh`, `build-app-bundle.sh`, `sign-app.sh`, `smoke-test.sh`
