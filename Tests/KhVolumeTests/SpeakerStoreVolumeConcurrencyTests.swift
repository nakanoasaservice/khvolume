import Testing
@testable import KhVolume

@Suite("SpeakerStore — Volume Concurrency", .serialized)
@MainActor
struct SpeakerStoreVolumeConcurrencyTests {

    // MARK: - Rapid preview

    /// Three previews are set before any task gets to run.
    /// Only the last one should reach setLevel because the earlier tasks are
    /// cancelled before they start.
    @Test("rapid previews commit only the last level")
    func rapidPreviewCommitsOnlyLastLevel() async {
        let mock = MockKhvolClient()
        mock.setLevelResult = .success(.stub(levels: [80]))
        let store = SpeakerStore.makeForTesting(client: mock)

        store.setVolumePreview(70)
        store.setVolumePreview(75)
        store.setVolumePreview(80)
        await store.awaitVolumeCommit()

        #expect(mock.setLevelCallCount == 1)
        #expect(mock.lastSetLevelArg == 80)
        #expect(store.pendingVolumeLevel == nil)
    }

    // MARK: - Stale commit results

    /// Regression test for the stale-result flicker bug:
    /// T1 (level=70) is in-flight when the user slides to 80.
    /// T1's HTTP response arrives after T2 has already started committing 80.
    /// T1's result must be discarded — it must not overwrite T2's .committing state.
    @Test("stale success from superseded commit is discarded")
    func staleSuccessDiscardedWhenSuperseded() async {
        let client = SuspendingKhvolClient()
        let store = SpeakerStore.makeForTesting(client: client)

        // T1 starts and suspends at setLevel(70)
        store.setVolumePreview(70)
        await Task.yield()
        #expect(client.pendingCommits.count == 1)

        // User moves slider to 80 → T1 cancelled, T2 starts and suspends at setLevel(80)
        store.setVolumePreview(80)
        await Task.yield()
        #expect(client.pendingCommits.count == 2)

        // T1's HTTP response arrives with stale data — must be discarded
        client.resumeNext(with: .success(.stub(levels: [70])))
        await Task.yield()

        // T2's response arrives with the correct data
        client.resumeNext(with: .success(.stub(levels: [80])))
        await store.awaitVolumeCommit()

        #expect(store.status.averageLevel == 80)
        #expect(store.pendingVolumeLevel == nil)
        #expect(store.connection == .ready)
    }

    /// T1 fails while T2 is already committing a newer level.
    /// T1's error must be discarded so it does not pollute the UI.
    @Test("stale failure from superseded commit is discarded")
    func staleFailureDiscardedWhenSuperseded() async {
        let client = SuspendingKhvolClient()
        let store = SpeakerStore.makeForTesting(client: client)

        store.setVolumePreview(70)
        await Task.yield()

        store.setVolumePreview(80)
        await Task.yield()

        // T1 fails — error must not surface to the user
        client.resumeNext(with: .failure(KhvolError.timedOut))
        await Task.yield()

        // T2 succeeds
        client.resumeNext(with: .success(.stub(levels: [80])))
        await store.awaitVolumeCommit()

        #expect(store.status.averageLevel == 80)
        #expect(store.status.lastError == nil)
        #expect(store.connection == .ready)
    }

    // MARK: - Cancel while committing

    /// cancelPendingVolume() is called while a setLevel request is in-flight.
    /// The commit result must be discarded; state must remain idle.
    @Test("cancel while committing goes idle; late result is discarded")
    func cancelWhileCommittingGoesIdle() async {
        let client = SuspendingKhvolClient()
        let store = SpeakerStore.makeForTesting(client: client)

        store.setVolumePreview(70)
        await Task.yield()  // T1 suspends at setLevel(70)

        store.cancelPendingVolume()
        #expect(store.pendingVolumeLevel == nil)

        // T1's late response arrives after cancel — must be discarded
        client.resumeNext(with: .success(.stub(levels: [70])))
        await Task.yield()

        #expect(store.pendingVolumeLevel == nil)
        // stale json (levels:[70]) was not applied — averageLevel stays at the initial 0
        #expect(store.status.averageLevel != 70)
    }

    /// When a commit is cancelled and the in-flight request later fails,
    /// the error must not be shown to the user.
    @Test("stale failure after cancel does not set error")
    func staleFailureAfterCancelDoesNotSetError() async {
        let client = SuspendingKhvolClient()
        let store = SpeakerStore.makeForTesting(client: client)

        store.setVolumePreview(70)
        await Task.yield()

        store.cancelPendingVolume()

        client.resumeNext(with: .failure(KhvolError.timedOut))
        await Task.yield()

        // The stale failure must not surface as a user-visible error
        #expect(store.status.lastError == nil)
    }

    // MARK: - refreshSilently guard

    /// While a setLevel is in-flight (volumeState = .committing), preparePopover
    /// must not trigger a jsonStatus fetch — the commit result will refresh state.
    @Test("refreshSilently is skipped while volume commit is in flight")
    func refreshSilentlySkippedWhileCommitting() async {
        let client = SuspendingKhvolClient()
        let store = SpeakerStore.makeForTesting(client: client)

        // T1 runs to setLevel(70) and suspends → volumeState = .committing
        store.setVolumePreview(70)
        await Task.yield()

        // preparePopover calls refreshSilently internally; it should be a no-op
        await store.preparePopover()
        #expect(client.jsonStatusCallCount == 0)

        // Clean up: let T1 finish
        client.resumeNext(with: .success(.stub(levels: [70])))
        await store.awaitVolumeCommit()
    }

    // MARK: - toggleMute interaction

    /// toggleMute() cancels any pending volume and runs a mute mutation.
    /// If an in-flight setLevel response arrives after the mute completes,
    /// it must not overwrite the mute state.
    @Test("toggleMute while committing discards the pending commit result")
    func toggleMuteWhileCommittingDiscardsPendingResult() async {
        let client = SuspendingKhvolClient()
        client.setMutedResult = .success(.stub(muted: true))
        let store = SpeakerStore.makeForTesting(client: client)
        store.status.isMuted = false

        // T1 starts and suspends at setLevel(70)
        store.setVolumePreview(70)
        await Task.yield()

        // toggleMute cancels the pending volume and runs setMuted
        await store.toggleMute()
        #expect(store.status.isMuted == true)
        #expect(store.pendingVolumeLevel == nil)

        // T1's late response arrives with stale data (muted: false) — must be discarded
        client.resumeNext(with: .success(.stub(levels: [70], muted: false)))
        await Task.yield()

        #expect(store.status.isMuted == true)
    }
}
