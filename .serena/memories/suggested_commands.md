# Suggested Commands

The Swift app is built from the Xcode project `KhVolume/KhVolume.xcodeproj` (scheme `KhVolume`). Run commands from the repo root.

## Swift app

```bash
open KhVolume/KhVolume.xcodeproj                     # Run debug build from Xcode
xcodebuild test -project KhVolume/KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS'  # Run all tests
xcodebuild test -project KhVolume/KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS' -only-testing:KhVolumeTests/SpeakerStoreVolumeConcurrencyTests  # Single suite
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
