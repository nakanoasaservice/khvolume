# Conventions

## Swift

- `@Observable` (Swift Observation framework) for `SpeakerStore` — not `ObservableObject`/`@Published`
- Protocol-based testability: `SpeakerControlling`, `NetworkMonitorService`, `HotkeyService`, `LaunchAtLoginManaging`; `SpeakerStore` also takes `listInterfaces` and `defaults`
- All tests are `async` (Swift Concurrency); tests run hosted in the app, which skips the real scenes under XCTest
- `SpeakerStore.makeForTesting` saves to a throwaway UserDefaults suite — hosted tests would otherwise write the real app's settings
- `MockSpeakerGroup` answers at once; `SuspendingSpeakerGroup` holds `setLevel` (and optionally `connect`) until resumed — use it for requests made while another is in flight
- Mocks used by `SpeakerStore` are `@MainActor`, so `await store.settle()` / `waitForPending()` sequence tests without sleeps

## SpeakerControlling

- `connect(interface:rescan:)` → ensure links for the interface, then read every speaker's output; throws `.noInterface` / `.noSpeakersFound`
- `setLevel(_:)` / `setMuted(_:)` → send to all speakers; outputs are updated from the set replies (speakers echo the applied value — checked by `SSCHardwareTests`), with a read as fallback
- `disconnect()` → close sockets (network change, sleep); links reconnect on the next request
- One instance for the app's lifetime; it holds the interface, links and outputs. Callers run one operation at a time (`SpeakerStore` does)

## File organisation

- Models: pure value types in `Models/`
- Services: business logic + side effects in `Services/`
- Views: SwiftUI only in `Views/`
- Test helpers in `Tests/KhVolumeTests/Helpers/`
