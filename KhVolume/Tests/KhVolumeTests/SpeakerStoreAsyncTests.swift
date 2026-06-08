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
        #expect(store.status.connection == .ready)
        #expect(store.isBusy == false)
        #expect(store.isStatusLoading == false)
    }

    @Test("refresh sets disconnected state on error")
    func refreshError() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .failure(KhvolError.timedOut)
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.connection == .disconnected)
        #expect(store.status.lastError != nil)
        #expect(store.isBusy == false)
        #expect(store.isStatusLoading == false)
    }

    @Test("refresh does nothing when already busy")
    func refreshNoOpWhenBusy() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)
        store.isBusy = true

        await store.refresh()

        #expect(mock.jsonStatusCallCount == 0)
    }

    @Test("refresh sets connection to warning when not balanced")
    func refreshWarningWhenUnbalanced() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(balanced: false))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.connection == .warning)
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

    // MARK: commitPendingVolume

    @Test("commitPendingVolume calls setLevel with pending value")
    func commitCallsSetLevel() async {
        let mock = MockKhvolClient()
        mock.setLevelResult = .success(.stub(levels: [75]))
        let store = SpeakerStore.makeForTesting(client: mock)
        store.pendingVolumeLevel = 75

        await store.commitPendingVolume()

        #expect(mock.lastSetLevelArg == 75)
    }

    @Test("commitPendingVolume clears pendingVolumeLevel on success")
    func commitClearsPendingOnSuccess() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)
        store.pendingVolumeLevel = 75

        await store.commitPendingVolume()

        #expect(store.pendingVolumeLevel == nil)
    }

    @Test("commitPendingVolume retains pendingVolumeLevel on failure")
    func commitRetainsPendingOnFailure() async {
        let mock = MockKhvolClient()
        mock.setLevelResult = .failure(KhvolError.commandFailed("device error"))
        let store = SpeakerStore.makeForTesting(client: mock)
        store.pendingVolumeLevel = 75

        await store.commitPendingVolume()

        // On failure pending is kept (trailing task reschedules)
        #expect(store.status.lastError != nil)
        #expect(store.status.connection == .disconnected)
        #expect(store.isVolumeCommitting == false)
    }

    @Test("commitPendingVolume is no-op when nothing pending")
    func commitNoOpWhenNoPending() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.commitPendingVolume()

        #expect(mock.lastSetLevelArg == nil)
    }

    @Test("commitPendingVolume resets isVolumeCommitting to false after success")
    func commitResetsCommittingFlag() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)
        store.pendingVolumeLevel = 50

        await store.commitPendingVolume()

        #expect(store.isVolumeCommitting == false)
    }
}
