# KH Volume — Core

macOS 14+ menu bar app controlling Neumann KH DSP studio monitors (KH 80/120 II/150/750) over IPv6 link-local via SSC (Sennheiser Sound Control). Adjusts DSP level directly, bypassing macOS system volume.

## Architecture

Pure Swift app (`KhVolume/Sources/KhVolume/`): UI + state machine on top of a native SSC client in `Services/SSC/`. There is no helper process (the former Python/PyInstaller helper was removed).

## Swift source map

| Path (relative to `KhVolume/Sources/KhVolume/`) | Role |
|---|---|
| `KhVolumeApp.swift` | `@main` entry (`KhVolumeMain`); `KhVolumeApp` wires `MenuBarExtra` + `Settings` scenes |
| `App/KhVolumeAppDelegate.swift` | NSApp delegate |
| `Models/SpeakerModels.swift` | `DeviceLevel`, `SpeakerStatus`, `NetworkInterfaceInfo`, `KhvolJSONStatus`, `ConnectionState` |
| `Models/AppConfig.swift` | Persisted settings: interface, maxVolumeLimit, volumeStep, launchAtLogin, allowForceOnMismatch, hotkeys |
| `Services/SpeakerStore.swift` | Central `@Observable` state; Phase FSM + Volume FSM — see `mem:fsm` |
| `Services/KhvolClient.swift` | `KhvolClientProtocol` + production client: status/level/mute via SSC, scan, interface list |
| `Services/SSC/SSCSocket.swift` | One BSD-socket TCP connection to a speaker (JSON line in/out). BSD sockets on purpose: NWConnection leaves half-open flows when the process dies and speakers only have 4 slots |
| `Services/SSC/SSCSpeakerPool.swift` | Shared persistent connections, one per speaker, per-speaker serial queue, one retry on a stale connection |
| `Services/SSC/SSCMessages.swift` | SSC JSON messages/parsing + `SpeakerStatusBuilder` |
| `Services/SSC/SSCBrowser.swift` | Bonjour `_ssc._tcp` scan via NWBrowser; resolves with a UDP NWConnection (no TCP slot used) |
| `Services/SSC/SpeakerDirectory.swift` | Scanned speaker list in UserDefaults (`speakers`: `{mDNS name: IPv6}`) |
| `Services/AppDefaults.swift` | `AppConfig` load/save in UserDefaults (`config`) |
| `Services/NetworkInterfaceLister.swift` | Hardware ports via SystemConfiguration + SIOCGIFMEDIA link state |
| `Services/VolumeAdjustable.swift` | Protocol used by hotkey and HUD paths |
| `Services/HotkeyService.swift` / `HotkeyManager.swift` | Global shortcuts via `KeyboardShortcuts` package |
| `Services/NetworkMonitorService.swift` | `NWPathMonitor` wrapper; triggers reconnect on network change |
| `Views/` | SwiftUI views: popover, menu bar label, settings sheet, HUD overlay |

## Test layout

`KhVolume/Tests/KhVolumeTests/` — all tests `async`, hosted in the app; `KhVolumeMain` launches an empty app instead of `KhVolumeApp` when `XCTestConfigurationFilePath` is set.
Helpers: `FakeSSCServer` (loopback SSC device for pool tests), `MockKhvolClient`, `SuspendingKhvolClient`, `MockNetworkMonitorService`, `MockHotkeyService`, `MockLaunchAtLoginCoordinator`.

## Further reading

- FSM details: `mem:fsm`
- Tech stack / versions: `mem:tech_stack`
- Commands: `mem:suggested_commands`
- Conventions: `mem:conventions`
- Task completion: `mem:task_completion`
