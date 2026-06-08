# Suggested Commands

All Swift commands must be run from the `KhVolume/` subdirectory (where `Package.swift` lives).

## Swift app

```bash
cd KhVolume && swift run                             # Run debug build
cd KhVolume && swift test                            # Run all tests
cd KhVolume && swift test --filter SpeakerStoreVolumeConcurrencyTests  # Single test class
```

## Build / distribute

```bash
./scripts/build-khvol-helper.sh   # Build Python helper (needed first time or after Helper/ changes)
./scripts/build-app-bundle.sh     # Build distributable .app (auto-builds helper if needed)
```

## Python helper (dev, no PyInstaller needed)

```bash
./KhVolume/Scripts/khvol-dev interfaces
./KhVolume/Scripts/khvol-dev scan --config-dir ~/.khvol-test -i en15
```

## Smoke test (requires real hardware)

```bash
export KHVOL_INTERFACE=en15
./scripts/smoke-test.sh
```

## App data location

`~/Library/Application Support/KHVolume/` — settings + scan cache
