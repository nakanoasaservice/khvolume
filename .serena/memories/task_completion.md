# Task Completion

After any coding change, run:

```bash
xcodebuild test -project KhVolume/KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS'
```

No linter or formatter is configured (no SwiftLint/SwiftFormat in the project).

Hardware-dependent behaviour (SSC, scanning) needs real speakers: run the app and check status, level, mute and rescan.
