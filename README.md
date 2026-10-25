# KH Volume

**KH Volume** is a macOS menu bar application designed to control the volume of **Neumann KH DSP** studio monitors. It is especially useful when your speakers are connected via **S/PDIF coaxial digital input** or USB, where the standard macOS volume keys no longer map to your monitors.

Instead of adjusting the system volume slider, KH Volume directly drives the **network DSP level** of your speakers using Sennheiser Sound Control (SSC) over IPv6. This provides a practical and precise way to change the listening level and toggle mute directly from your Mac's menu bar.

**Thanks to [Thorsten Schwinn](https://github.com/schwinn)** and the contributors of [**khtool**](https://github.com/schwinn/khtool) — the open-source Python tool that communicates with Georg Neumann KH speakers over SSC. Earlier versions of KH Volume bundled khtool; the app now speaks SSC natively in Swift, but without that project it would not exist.

![KH Volume menu bar popover showing volume slider and network picker](image/screenshot.png)

## Supported Monitors

If your KH monitors are connected to your local network via Ethernet (built-in port or adapter) and support SSC, KH Volume can seamlessly manage their levels. This includes popular models across the Neumann KH DSP lineup: **KH 80 DSP**, **KH 120 II**, **KH 150**, **KH 150 AES67**, and **KH 750 DSP**.

## How it works

1. Your Mac and the speakers share a network connection (usually Ethernet to the speaker’s RJ45 port).
2. KH Volume finds the speakers via Bonjour (`_ssc._tcp`) and keeps one SSC connection open to each, sending commands over the LAN.
3. The app displays the current DSP level in the menu bar, featuring a popover similar to the native macOS Sound interface.
4. Optional global shortcuts (default **⌥=** / **⌥-**) allow you to adjust the level without opening the popover.

**Important:** The control mechanism operates entirely over the network control plane, independent of the audio bitstream. This means your Mac can output pristine audio via a digital S/PDIF connection while the volume level is managed separately over Ethernet via SSC.

## Features

- Menu bar level display and slider for quick access
- Mute toggle functionality
- Network interface picker (supports USB Ethernet adapters, built-in LAN, etc.)
- Per-app volume cap (“volume limit”) and customizable step sizes (1 / 3 / 6 dB)
- Global keyboard shortcuts (customizable in Sound Settings)
- Open at Login support (requires a signed app in `/Applications`)
- Left/right level mismatch warning for stereo pairs

## Requirements

- **macOS 14** or later
- Neumann KH DSP monitors reachable on your LAN via SSC (IPv6 link-local)
- A Mac network interface capable of reaching the speakers (e.g., USB–Ethernet adapter, `en15`, `en0`)
- To **build from source:** Xcode 26+

## Install (release)

Pre-built signed releases may be published separately. To build locally:

```bash
./scripts/build-app-bundle.sh
open "dist/KH Volume.app"
```

For distribution signing and notarization, see `scripts/sign-app.sh`.

## Development

```bash
# Open in Xcode and run the KhVolume scheme
open KhVolume/KhVolume.xcodeproj

# Run tests
xcodebuild test -project KhVolume/KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS'
```

App data and scan cache: `~/Library/Application Support/KHVolume/`

## Troubleshooting

| Symptom | Things to check |
|--------|------------------|
| Menu bar shows `!` | Speaker off, wrong network interface, or no route to the speaker |
| No speakers in **Network** list | Cable/link down; pick the interface that has link (`ifconfig`) |
| Level does not change | Pick the network interface again to rescan; allow **Local Network** access for KH Volume in System Settings → Privacy & Security |
| **Open at Login** fails | Install a **Developer ID–signed** `KH Volume.app` in `/Applications` |
| Left/right levels differ | Use decrease-only until matched, or enable “allow increase when mismatched” in settings |

## Project layout

```
KhVolume/              Swift menu bar app
  KhVolume.xcodeproj   Xcode project (app + unit tests)
  Sources/             App UI and logic
  Tests/               Unit tests (Swift Testing)
scripts/               build-app-bundle.sh, sign-app.sh
```

## Credits

- Speaker control protocol: **SSC** (Sennheiser Sound Control), used by **Georg Neumann GmbH** KH DSP products.
- Protocol reference: [khtool](https://github.com/schwinn/khtool) by **Thorsten Schwinn** et al. and [pyssc](https://github.com/schwinn/pyssc).
- App: native SwiftUI menu bar app with a built-in SSC client.

## License

KH Volume is released under the [MIT License](LICENSE). See [NOTICES](NOTICES) for third-party components and acknowledgements.

This project is **not affiliated with** Georg Neumann GmbH, Sennheiser, or Neumann. Neumann product names are trademarks of their respective owners. Use of SSC to control your hardware is at your own risk.
