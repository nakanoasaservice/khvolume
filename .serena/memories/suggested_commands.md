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
./scripts/build-app-bundle.sh     # Build distributable .app
```

## App data location

UserDefaults (standard domain of the app bundle id): `config` (AppConfig as a plist dictionary) and `speakers` (`{mDNS name: IPv6}`)
