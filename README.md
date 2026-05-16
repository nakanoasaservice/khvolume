# KH Volume

**Menu bar volume control for Neumann KH DSP monitors on macOS** — especially when you use **S/PDIF coaxial digital input** and macOS volume keys no longer map to your speakers.

KH Volume drives the speaker’s **network DSP level** (Sennheiser Sound Control / SSC over IPv6), not the macOS system volume slider. That is the practical way to change level when audio is fed over **digital coax**, USB, or any input where the Mac’s volume control does not reach the monitors.

**Thanks to [Thorsten Schwinn](https://github.com/schwinn)** and the contributors of [**khtool**](https://github.com/schwinn/khtool) — the open-source Python tool that talks to Neumann KH DSP speakers over SSC. KH Volume is a native macOS menu bar shell around a bundled `khvol` helper that builds on vendored khtool (MIT). Without that project, this app would not exist.

## Who is this for?

You might be searching for:

- **Neumann KH 120 II volume control on Mac**
- **KH 750 DSP macOS volume**
- **S/PDIF coaxial digital input volume** (no response to ⌘ volume keys)
- **KH monitor menu bar volume**
- **Georg Neumann KH digital input level control**

If your KH speakers are on **Ethernet** (built-in port or adapter) and support SSC — as **KH 80 DSP**, **KH 120 II**, **KH 150**, **KH 150 AES67**, **KH 750 DSP**, and related KH DSP models do — KH Volume can set level and mute from the menu bar with optional global shortcuts.

## Supported monitors (examples)

KH Volume talks to Neumann **KH DSP** loudspeakers that expose SSC on the LAN, including:

| Model | Notes |
|--------|--------|
| **KH 80 DSP** | Compact nearfield |
| **KH 120 II** | Common studio monitor; digital inputs incl. S/PDIF coax |
| **KH 150** | Mid-size DSP monitor |
| **KH 150 AES67** | AES67 networking variant |
| **KH 750 DSP** | Subwoofer; level/mute via SSC (some settings differ from full-range models) |

Other KH DSP models that appear in a network scan with [khtool](KhVolume/Helper/vendor/khtool.py) are generally supported for **level** and **mute**.

## How it works

1. Mac and speakers share a network (usually **Ethernet** to the speaker’s RJ45).
2. KH Volume runs a bundled **`khvol`** helper (Python + [khtool](KhVolume/Helper/vendor/)) to send SSC commands.
3. The app shows the current DSP level in the **menu bar**, with a popover like macOS Sound.
4. Optional shortcuts (default **⌥=** / **⌥-**) adjust level without opening the popover.

**Important:** Control is over the **network control plane**, not over the S/PDIF bitstream. Your Mac can play audio via **S/PDIF coaxial digital** while level is adjusted separately via Ethernet/SSC. Both cables/connections are used for different jobs.

## Features

- Menu bar level display and slider
- Mute toggle
- **Network** interface picker (USB Ethernet, built-in LAN, etc.)
- Per-app volume cap (“volume limit”) and step size (1 / 3 / 6 dB)
- Global shortcuts (customizable in Sound Settings)
- Open at Login (requires signed app in `/Applications`)
- Left/right level mismatch warning (stereo pairs)

## Requirements

- **macOS 14** or later
- Neumann **KH DSP** monitors reachable on your LAN (SSC / IPv6 link-local)
- A Mac network interface that can reach the speakers (e.g. USB–Ethernet adapter, `en15`, `en0`)
- To **build from source:** Xcode Command Line Tools / Swift 5.9+, Python 3.12+ (for the bundled helper only)

## Install (release)

Pre-built signed releases may be published separately. To build locally:

```bash
./scripts/build-khvol-helper.sh
./scripts/build-app-bundle.sh
open dist/KhVolume.app
```

For distribution signing and notarization, see `scripts/sign-app.sh`.

## Development

```bash
# Build PyInstaller helper (first time or after KhVolume/Helper/ changes)
./scripts/build-khvol-helper.sh

# Run the app
cd KhVolume && swift run

# Optional: run helper CLI from source
./KhVolume/Scripts/khvol-dev interfaces
./KhVolume/Scripts/khvol-dev scan --config-dir ~/.khvol-test -i en15
```

App data and scan cache: `~/Library/Application Support/KHVolume/`

Smoke test (hardware or offline-tolerant):

```bash
export KHVOL_INTERFACE=en15   # your USB-LAN interface name
./scripts/smoke-test.sh
```

## Troubleshooting

| Symptom | Things to check |
|--------|------------------|
| Menu bar shows `!` | Speaker off, wrong network interface, or no route to the speaker |
| No speakers in **Network** list | Cable/link down; pick the interface that has link (`ifconfig`) |
| Level does not change | Confirm `--scan` finds devices; try the interface where `khtool` works |
| **Open at Login** fails | Install a **Developer ID–signed** `KhVolume.app` in `/Applications` |
| Left/right levels differ | Use decrease-only until matched, or enable “allow increase when mismatched” in settings |

## Project layout

```
KhVolume/              Swift menu bar app (Swift Package Manager)
  Sources/             App UI and logic
  Helper/              khvol CLI + vendor/khtool (bundled into the app)
  Scripts/             khvol-dev — run CLI from source without PyInstaller
scripts/               build-app-bundle.sh, sign-app.sh, smoke-test.sh
```

## Credits

- Speaker control protocol: **SSC** (Sennheiser Sound Control), used by **Georg Neumann GmbH** KH DSP products.
- Low-level tool: [khtool](https://github.com/schwinn/khtool) by **Thorsten Schwinn** et al. (vendored under `KhVolume/Helper/vendor/`).
- App: native SwiftUI menu bar shell around the bundled `khvol` helper.

## License

KH Volume is released under the [MIT License](LICENSE). See [NOTICES](NOTICES) for bundled third-party components (including [khtool](https://github.com/schwinn/khtool) and [pyssc](https://github.com/schwinn/pyssc)).

This project is **not affiliated with** Georg Neumann GmbH, Sennheiser, or Neumann. Neumann product names are trademarks of their respective owners. Use of SSC to control your hardware is at your own risk.
