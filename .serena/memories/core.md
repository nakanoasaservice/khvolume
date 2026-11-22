# KH Volume — Core

macOS 14+ menu bar app controlling Neumann KH DSP studio monitors (KH 80/120 II/150/750) over IPv6 link-local via SSC (Sennheiser Sound Control). Adjusts DSP level directly, bypassing macOS system volume.

## Architecture

Pure Swift app (`Sources/KhVolume/`): UI + `SpeakerStore` on top of `SpeakerGroup`, which owns the SSC connections (`Services/SSC/`). There is no helper process (the former Python/PyInstaller helper was removed).

## Swift source map

| Path (relative to `Sources/KhVolume/`) | Role |
|---|---|
| `KhVolumeApp.swift` | `@main` entry (`KhVolumeMain`); `KhVolumeApp` wires `MenuBarExtra` + `Settings` scenes |
| `Models/SpeakerModels.swift` | `Speaker`, `SpeakerOutput` (+ derived group level/mute/balance), `ConnectionState`, `SpeakerError`, `NetworkInterfaceInfo` |
| `Models/AppConfig.swift` | Persisted settings: interface, maxVolumeLimit, volumeStep, launchAtLogin, allowForceOnMismatch (hotkeys are stored by KeyboardShortcuts) |
| `Services/SpeakerStore.swift` | Central `@Observable` state; target level + serialized speaker operations — see `mem:speaker_store` |
| `Services/SpeakerGroup.swift` | `SpeakerControlling` + `SpeakerGroup` actor: owns the links and last reported outputs; connect/scan, set level, set mute |
| `Services/SSC/SSCSocket.swift` | One BSD-socket TCP connection to a speaker (JSON line in/out). BSD sockets on purpose: NWConnection leaves half-open flows when the process dies and speakers only have 4 slots |
| `Services/SSC/SpeakerLink.swift` | Persistent connection to one speaker: serial queue, device name asked once, one retry on a stale connection |
| `Services/SSC/SSCMessages.swift` | SSC JSON messages/parsing |
| `Services/SSC/SSCBrowser.swift` | Bonjour `_ssc._tcp` scan via NWBrowser; resolves with a UDP NWConnection (no TCP slot used) |
| `Services/SSC/SpeakerDirectory.swift` | Scanned speaker list in UserDefaults (`speakers`: `{mDNS name: IPv6}`) |
| `Services/AppDefaults.swift` | `AppConfig` load/save in UserDefaults (`config`) |
| `Services/NetworkInterfaceLister.swift` | Hardware ports via SystemConfiguration + SIOCGIFMEDIA link state |
| `Services/HotkeyService.swift` / `HotkeyManager.swift` | Global shortcuts via `KeyboardShortcuts` package |
| `Services/NetworkMonitorService.swift` | `NWPathMonitor` wrapper; triggers reconnect on network change (sleep is observed in `SpeakerStore`) |
| `Views/` | SwiftUI views: popover, menu bar label, settings sheet, HUD overlay |

## Test layout

`Tests/KhVolumeTests/` — all tests `async`, hosted in the app; `KhVolumeMain` launches an empty app instead of `KhVolumeApp` when `XCTestConfigurationFilePath` is set.
Helpers: `FakeSSCServer` (loopback SSC device for `SpeakerGroup` tests), `MockSpeakerGroup`, `SuspendingSpeakerGroup`, `MockNetworkMonitorService`, `MockHotkeyService`, `MockLaunchAtLoginCoordinator`.

## Further reading

- Store state, operation ordering, rescan policy: `mem:speaker_store`
- Tech stack / versions: `mem:tech_stack`
- Commands: `mem:suggested_commands`
- Conventions: `mem:conventions`
- Task completion: `mem:task_completion`
