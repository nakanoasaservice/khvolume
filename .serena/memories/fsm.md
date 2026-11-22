# SpeakerStore FSMs

Both FSMs live in `Sources/KhVolume/Services/SpeakerStore.swift`.

## Phase FSM — serialises load operations

States: `idle` | `loading(LoadReason)`

LoadReason cases:
- `.refresh`
- `.interfaceSelection(name:)`
- `.mutation`

Events (`PhaseEvent`): `loadBegan` / `loadCompleted` / `silentRefreshCompleted`
Reducer: `SpeakerStore.reduce(_:)`

Key invariant: `refreshSilently` is a no-op while `phase == .loading(.mutation)` (committing) to avoid UI flicker.

## Volume FSM — throttles slider drags

States: `idle` | `pending(level:lastCommitStart:)` | `committing(level:commitStart:)`

Transitions:
- `setVolumePreview` → `pending`; while disconnected it schedules a refresh instead, because no level is known
- `scheduleVolumeCommit` fires after `SpeakerStoreTiming.volumeThrottleInterval` → `committing`
- Commit result arrives: compare `commitStart` timestamp; if superseded → discard silently → stay/return to idle
- Commit fails → `idle` (the level is dropped) and the connection becomes disconnected
- `cancelPendingVolume` → `idle`

Events (`VolumeEvent`): reducer `SpeakerStore.reduceVolume(_:)`

Timing struct: `SpeakerStoreTiming` — `volumeThrottleInterval`, `networkRecoveryDelay`; `testing` static instance with shortened intervals for tests.
