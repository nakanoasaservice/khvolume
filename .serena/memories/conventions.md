# Conventions

## Swift

- `@Observable` (Swift Observation framework) for `SpeakerStore` — not `ObservableObject`/`@Published`
- Protocol-based testability: `KhvolClientProtocol`, `VolumeAdjustable`, `NetworkMonitorServiceProtocol`, `HotkeyServiceProtocol`, `LaunchAtLoginCoordinatorProtocol`
- All tests are `async` (Swift Concurrency); test target compiled with `-D TESTING` which removes `@main`
- `SuspendingKhvolClient` suspends until manually resumed — use for concurrency invariant tests
- Stale-result discarding pattern: volume commit results carry a `commitStart` timestamp; results superseded by a newer commit or cancel are silently dropped

## FSM style

- Enums for states and events; `reduce(_:)` / `reduceVolume(_:)` are pure functions on `SpeakerStore`
- Phase FSM serialises load operations (idle ↔ loading); Volume FSM throttles slider drags

## Python helper interface

`KhvolClient` calls these subcommands; stdout is always JSON:
- `json` → status (levels, muted, balanced, devices)
- `scan` → rescan LAN, write `khtool.json`; exit 2 if no speakers found
- `interfaces` → list of network interfaces with link status
- `set LEVEL` → set absolute dB level, emit status JSON
- `mute` / `unmute` → toggle mute, emit status JSON

## File organisation

- Models: pure value types in `Models/`
- Services: business logic + side effects in `Services/`
- Views: SwiftUI only in `Views/`
- Test helpers in `Tests/KhVolumeTests/Helpers/`
