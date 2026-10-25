# Tech Stack

## Swift app

- Swift 5 language mode, macOS 14+ deployment target, built with Xcode 26+ (newer SDK enables Liquid Glass on macOS 26+)
- Swift Observation (`@Observable`) — NOT `ObservableObject`
- Project: `KhVolume/KhVolume.xcodeproj` (targets `KhVolume` app, `KhVolumeTests` hosted unit tests). Do not build with SwiftPM: `swift build` records the deployment target as the SDK version, which disables the current system design
- Dependencies (Swift packages added in the Xcode project):
  - `KeyboardShortcuts` ≥ 2.0 (sindresorhus/KeyboardShortcuts) — global hotkeys
  - `Network` framework (linked explicitly via `linkerSettings`)

## Speaker protocol

- SSC (JSON over TCP port 45, IPv6 link-local scoped with `%<interface>`); Bonjour service `_ssc._tcp`
- KH speakers accept at most 4 concurrent TCP connections; a 5th SYN is silently ignored
- `Info.plist` declares `NSLocalNetworkUsageDescription` and `NSBonjourServices`

## Build tooling

- Shell scripts in `scripts/`: `build-app-bundle.sh`, `sign-app.sh`
