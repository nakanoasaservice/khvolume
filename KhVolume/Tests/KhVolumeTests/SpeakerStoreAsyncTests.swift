import Testing
@testable import KhVolume

@Suite("SpeakerStore — Async Operations", .serialized)
@MainActor
struct SpeakerStoreAsyncTests {

    // MARK: refresh

    @Test("refresh updates status on success")
    func refreshSuccess() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(levels: [80], muted: false, balanced: true))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.averageLevel == 80)
        #expect(store.connection == .ready)
        #expect(store.isStatusLoading == false)
        #expect(store.isStatusLoading == false)
    }

    @Test("refresh sets disconnected state on error")
    func refreshError() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .failure(KhvolError.timedOut)
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.connection == .disconnected)
        #expect(store.status.lastError != nil)
        #expect(store.isStatusLoading == false)
        #expect(store.isStatusLoading == false)
    }

    @Test("refresh does nothing when already busy")
    func refreshNoOpWhenBusy() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)
        store.phase = .loading(.refresh)

        await store.refresh()

        #expect(mock.jsonStatusCallCount == 0)
    }

    @Test("refresh sets connection to warning when not balanced")
    func refreshWarningWhenUnbalanced() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(balanced: false))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.connection == .warning)
    }

    // MARK: toggleMute

    @Test("toggleMute calls setMuted with inverted mute state")
    func toggleMuteCallsSetMuted() async {
        let mock = MockKhvolClient()
        mock.setMutedResult = .success(.stub(muted: true))
        let store = SpeakerStore.makeForTesting(client: mock)
        store.status.isMuted = false

        await store.toggleMute()

        #expect(mock.lastSetMutedArg == true)
    }

    @Test("toggleMute clears pendingVolumeLevel")
    func toggleMuteClearsPending() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)
        store.pendingVolumeLevel = 60

        await store.toggleMute()

        #expect(store.pendingVolumeLevel == nil)
    }

    @Test("toggleMute updates isMuted from response")
    func toggleMuteUpdatesStatus() async {
        let mock = MockKhvolClient()
        mock.setMutedResult = .success(.stub(muted: true))
        let store = SpeakerStore.makeForTesting(client: mock)
        store.status.isMuted = false

        await store.toggleMute()

        #expect(store.status.isMuted == true)
    }

    // MARK: Volume commit

    @Test("setVolumePreview commits pending level via setLevel")
    func commitCallsSetLevel() async {
        let mock = MockKhvolClient()
        mock.setLevelResult = .success(.stub(levels: [75]))
        let store = SpeakerStore.makeForTesting(client: mock)

        store.setVolumePreview(75)
        await store.awaitVolumeCommit()

        #expect(mock.lastSetLevelArg == 75)
    }

    @Test("pendingVolumeLevel is cleared after successful commit")
    func commitClearsPendingOnSuccess() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)

        store.setVolumePreview(75)
        await store.awaitVolumeCommit()

        #expect(store.pendingVolumeLevel == nil)
    }

    @Test("pendingVolumeLevel is retained after failed commit")
    func commitRetainsPendingOnFailure() async {
        let mock = MockKhvolClient()
        mock.setLevelResult = .failure(KhvolError.commandFailed("device error"))
        let store = SpeakerStore.makeForTesting(client: mock)

        store.setVolumePreview(75)
        await store.awaitVolumeCommit()

        #expect(store.pendingVolumeLevel == 75)
        #expect(store.status.lastError != nil)
        #expect(store.connection == .disconnected)
        #expect(store.isStatusLoading == false)
    }

    @Test("no commit occurs when no pending level")
    func commitNoOpWhenNoPending() async {
        let mock = MockKhvolClient()
        _ = SpeakerStore.makeForTesting(client: mock)
        // pendingVolumeLevel is nil by default — nothing to commit
        #expect(mock.lastSetLevelArg == nil)
    }

    @Test("volume commit does not affect loading phase")
    func commitDoesNotAffectLoadingPhase() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)

        store.setVolumePreview(50)
        await store.awaitVolumeCommit()

        #expect(store.isStatusLoading == false)
        #expect(store.isStatusLoading == false)
    }
}
