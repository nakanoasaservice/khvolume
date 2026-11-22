# KH Volume — notes for agents

macOS menu bar app that sets the DSP level of Neumann KH speakers over SSC (Sennheiser Sound Control). Pure Swift; the README covers what it does for users. This file holds only what the code does not show.

## Build and test

```bash
# All tests
xcodebuild test -project KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS'

# One suite
xcodebuild test -project KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS' -only-testing:KhVolumeTests/SpeakerGroupTests

# Against real speakers (skipped unless the interface is given)
TEST_RUNNER_KHVOL_HARDWARE_INTERFACE=en15 xcodebuild test -project KhVolume.xcodeproj -scheme KhVolume -destination 'platform=macOS' -only-testing:KhVolumeTests/SSCHardwareTests

# Distributable app in dist/
./scripts/build-app-bundle.sh
```

- Run all tests after any code change. There is no linter or formatter.
- The hardware test lowers the level by 1 dB and mutes for a moment, then restores both. Run it when a change touches `Services/SSC/` or `SpeakerGroup`.
- **Do not add a `Package.swift`.** `swift build` records the deployment target (macOS 14) as the linked SDK version, so macOS 26+ treats the app as built with an old SDK and drops the current system design. The Xcode project records the real SDK.
- **The Xcode project lists every source file.** Adding, renaming or removing a Swift file also needs the matching entries in `KhVolume.xcodeproj/project.pbxproj`, or the build breaks.
- Swift 5 language mode, macOS 14 minimum, Xcode 26+.

## Running the app by hand

- The debug build has the same bundle id as an installed `/Applications/KH Volume.app`, so both would register the same global hotkeys and share settings. Quit the installed one first.
- Settings live in UserDefaults: `defaults read com.khvolume.app` shows `config` (`AppConfig`) and `speakers` (`{mDNS name: IPv6 address}` from the last scan). Settings saved by earlier versions must keep loading.
- It is a menu bar app (`LSUIElement`): there is no window to look for after launch.

## Speakers and SSC

- SSC is one JSON line out, one back, over TCP port 45 on IPv6 link-local (the address needs `%<interface>`). Speakers advertise `_ssc._tcp` over Bonjour.
- **A speaker accepts 4 TCP connections; a 5th is ignored without an error.** Hence one long-lived connection per speaker, closed before sleep.
- Connections use BSD sockets, not `NWConnection`, on purpose: the kernel closes BSD sockets when the process dies, while `NWConnection` flows that are never cancelled stay half-open and use up the slots.
- The Bonjour scan resolves addresses with a UDP `NWConnection`, which sends nothing and takes no slot.
- **KH 750 support is untested on hardware.** Its output node (`audio.out` or `audio.out5`, by firmware) is copied from khtool's `handle_device`; nobody has run this app against a KH 750. On the `out5` firmware `out1`…`out4` are the monitors connected to the subwoofer, which the app does not touch.
- A speaker answers a set with the value it applied, so a volume change is one round trip (about 20 ms). `SSCHardwareTests` checks this.

## Rules the store relies on

- Every speaker operation in `SpeakerStore` goes through `enqueue`, so one finishes and applies its result before the next starts. Do not call `speakers` from anywhere else, except `disconnect`.
- A volume change only sets `targetLevel`; one loop sends the latest target. There is no timer or throttle: the round trip is the backpressure.
- The group's level is the quietest speaker's, not the average, so a level at or below it never makes a speaker louder. "Decrease only while left and right differ" depends on this.
- While not connected, volume and mute input reads the speakers instead of sending anything, because no level is known.
- A scan (a 3 s Bonjour browse) runs only when the user picks an interface, presses the reload button, or no speakers are stored.

## Tests

- Tests run inside the app as their host; `KhVolumeMain` starts an empty app when `XCTestConfigurationFilePath` is set. So **`UserDefaults.standard` in a test is the real app's settings**: use `UserDefaults.makeForTesting()` and `SpeakerStore.makeForTesting`.
- The mocks used with `SpeakerStore` are `@MainActor`, so `await store.settle()` and `SuspendingSpeakerGroup.waitForPending()` order a test without sleeps.
- `FakeSSCServer` is a loopback SSC device for `SpeakerGroup` tests.
