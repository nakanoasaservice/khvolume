# Conventions

## Swift

- `@Observable` (Swift Observation framework) for `SpeakerStore` — not `ObservableObject`/`@Published`
- Protocol-based testability: `KhvolClientProtocol`, `VolumeAdjustable`, `NetworkMonitorServiceProtocol`, `HotkeyServiceProtocol`, `LaunchAtLoginCoordinatorProtocol`
- All tests are `async` (Swift Concurrency); tests run hosted in the app, which skips the real scenes under XCTest
- `SuspendingKhvolClient` suspends until manually resumed — use for concurrency invariant tests
- Stale-result discarding pattern: volume commit results carry a `commitStart` timestamp; results superseded by a newer commit or cancel are silently dropped

## FSM style

- Enums for states and events; `reduce(_:)` / `reduceVolume(_:)` are pure functions on `SpeakerStore`
- Phase FSM serialises load operations (idle ↔ loading); Volume FSM throttles slider drags

## KhvolClientProtocol

- `jsonStatus()` → status (levels, muted, balanced, devices keyed by SSC device name)
- `scan()` → Bonjour scan, write `khtool.json`; throws `.deviceError` if no speakers found
- `interfaces()` → network interfaces with link status
- `setLevel(_:)` / `setMuted(_:)` → send to all speakers, then return fresh status
- `resetConnections()` → drop pooled connections (called on network path changes)
- Error messages containing "run scan" trigger an automatic rescan in `SpeakerStore.shouldRescan`

## File organisation

- Models: pure value types in `Models/`
- Services: business logic + side effects in `Services/`
- Views: SwiftUI only in `Views/`
- Test helpers in `Tests/KhVolumeTests/Helpers/`
