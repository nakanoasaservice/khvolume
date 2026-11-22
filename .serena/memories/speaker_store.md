# SpeakerStore — speaker operations

`Sources/KhVolume/Services/SpeakerStore.swift`. No state machines: the state is `connection`, `outputs` and `targetLevel`; everything else is derived.

## State

- `outputs: [SpeakerOutput]` — what the speakers last reported; empty = nothing known. `level` / `isMuted` / `isBalanced` are derived (`Collection where Element == SpeakerOutput`)
- Group level = the quietest speaker's (not the average), so a level at or below it never makes a speaker louder; this is what makes "decrease only while unbalanced" true
- `targetLevel` — the level the user asked for until the speakers confirm it; `level` is `targetLevel ?? outputs.level`
- `connection`: `disconnected` (nothing read yet) | `searching` (controls disabled; initial connect or rescan) | `connected` | `failed(SpeakerError)`. Balance is not a connection state

## One speaker operation at a time

- Every speaker call goes through `enqueue`, a task chain: an operation starts only after the previous one finished and applied its result. No stale results, no cancellation
- Level writes: `setLevel` only sets `targetLevel` and starts `writeTargetLevel` if none is running; the loop sends the latest target until the speakers have it. Levels asked for during a request replace the target → one following request. No timer or throttle: the round trip (~20 ms on real speakers) is the backpressure
- `refresh()` is skipped while a refresh is queued or a level is being written
- A failure (`fail`) sets `.failed`, clears `outputs` and `targetLevel`. While not connected, volume/mute input triggers `refresh()` instead of sending anything (no level is known)
- `disconnect` (network change, sleep) bypasses the chain: closing is safe at any time and returns nothing
- `settle()` waits for the chain; tests use it instead of sleeping

## Rescan policy

- `SpeakerGroup.connect(interface:rescan:)` uses the stored speakers; it scans (3 s Bonjour browse) only when none are stored or `rescan` is set
- `selectInterface` is the only caller with `rescan: true`
