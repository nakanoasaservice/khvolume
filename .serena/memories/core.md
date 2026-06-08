# KH Volume — Core

macOS 14+ menu bar app controlling Neumann KH DSP studio monitors (KH 80/120 II/150/750) over IPv6 link-local via SSC (Sennheiser Sound Control). Adjusts DSP level directly, bypassing macOS system volume.

## Two-layer architecture

- **Swift app** (`KhVolume/Sources/KhVolume/`) — UI + state machine. Never talks to speakers directly; spawns Python helper as subprocess and parses JSON.
- **Python helper** (`KhVolume/Helper/`) — `khvol_cli.py` wrapping pyssc/khtool. Packaged by PyInstaller → `KhVolume/Helpers/khvol-bundle/` (onedir), shell wrapper at `KhVolume/Helpers/khvol`.

## Swift source map

| Path (relative to `KhVolume/Sources/KhVolume/`) | Role |
|---|---|
| `KhVolumeApp.swift` | `@main` entry; wires `MenuBarExtra` + `Settings` scenes |
| `App/KhVolumeAppDelegate.swift` | NSApp delegate |
| `Models/SpeakerModels.swift` | `DeviceLevel`, `SpeakerStatus`, `NetworkInterfaceInfo`, `KhvolJSONStatus`, `ConnectionState` |
| `Models/AppConfig.swift` | Persisted settings: interface, maxVolumeLimit, volumeStep, launchAtLogin, allowForceOnMismatch, hotkeys |
| `Services/SpeakerStore.swift` | Central `@Observable` state; Phase FSM + Volume FSM — see `mem:fsm` |
| `Services/KhvolClient.swift` | Subprocess execution + JSON parsing; `KhvolClientProtocol` for testability |
| `Services/VolumeAdjustable.swift` | Protocol used by hotkey and HUD paths |
| `Services/HotkeyService.swift` / `HotkeyManager.swift` | Global shortcuts via `KeyboardShortcuts` package |
| `Services/NetworkMonitorService.swift` | `NWPathMonitor` wrapper; triggers reconnect on network change |
| `Views/` | SwiftUI views: popover, menu bar label, settings sheet, HUD overlay |

## Test layout

`KhVolume/Tests/KhVolumeTests/` — all tests `async`, built with `TESTING` compile flag (removes `@main`).
Helpers: `MockKhvolClient`, `SuspendingKhvolClient`, `MockNetworkMonitorService`, `MockHotkeyService`, `MockLaunchAtLoginCoordinator`.

## Further reading

- FSM details: `mem:fsm`
- Tech stack / versions: `mem:tech_stack`
- Commands: `mem:suggested_commands`
- Conventions: `mem:conventions`
- Task completion: `mem:task_completion`
