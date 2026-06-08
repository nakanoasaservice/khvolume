import Testing
@testable import KhVolume

@Suite("SpeakerStore — Volume Preview / Adjust / Cancel")
@MainActor
struct SpeakerStoreVolumePreviewTests {

    // MARK: setVolumePreview — basic

    @Test("setVolumePreview sets pendingVolumeLevel")
    func setVolumePreviewBasic() {
        let store = SpeakerStore.makeForTesting()
        store.setVolumePreview(75)
        #expect(store.pendingVolumeLevel == 75)
        #expect(store.status.lastError == nil)
    }

    @Test("setVolumePreview clamps to effectiveMax")
    func setVolumePreviewClampedToMax() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.setVolumePreview(130)
        #expect(store.pendingVolumeLevel == 100)
    }

    @Test("setVolumePreview clamps to 0")
    func setVolumePreviewClampedToZero() {
        let store = SpeakerStore.makeForTesting()
        store.setVolumePreview(-10)
        #expect(store.pendingVolumeLevel == 0)
    }

    @Test("setVolumePreview is no-op when isStatusLoading")
    func setVolumePreviewBlockedByLoading() {
        let store = SpeakerStore.makeForTesting()
        store.isStatusLoading = true
        store.setVolumePreview(50)
        #expect(store.pendingVolumeLevel == nil)
    }

    // MARK: setVolumePreview — mismatch guards

    @Test("setVolumePreview blocks increase when level mismatch and force not allowed")
    func setVolumePreviewBlockedByMismatch() {
        var config = AppConfig()
        config.allowForceOnMismatch = false
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        store.status.averageLevel = 60
        store.setVolumePreview(70)
        #expect(store.pendingVolumeLevel == nil)
        #expect(store.status.lastError != nil)
    }

    @Test("setVolumePreview allows decrease even with level mismatch")
    func setVolumePreviewAllowsDecreaseDespiteMismatch() {
        var config = AppConfig()
        config.allowForceOnMismatch = false
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        store.status.averageLevel = 60
        store.setVolumePreview(50)
        #expect(store.pendingVolumeLevel == 50)
    }

    @Test("setVolumePreview allows increase when allowForceOnMismatch is true")
    func setVolumePreviewAllowsIncreaseWithForce() {
        var config = AppConfig()
        config.allowForceOnMismatch = true
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        store.status.averageLevel = 60
        store.setVolumePreview(70)
        #expect(store.pendingVolumeLevel == 70)
    }

    // MARK: adjustVolume

    @Test("adjustVolume adds delta to status.averageLevel when no pending")
    func adjustVolumeFromAverage() {
        let store = SpeakerStore.makeForTesting()
        store.status.averageLevel = 50
        store.adjustVolume(by: 5)
        #expect(store.pendingVolumeLevel == 55)
    }

    @Test("adjustVolume adds delta to pendingVolumeLevel when already pending")
    func adjustVolumeFromPending() {
        let store = SpeakerStore.makeForTesting()
        store.status.averageLevel = 50
        store.pendingVolumeLevel = 60
        store.adjustVolume(by: 5)
        #expect(store.pendingVolumeLevel == 65)
    }

    @Test("adjustVolume with negative delta decreases volume")
    func adjustVolumeDown() {
        let store = SpeakerStore.makeForTesting()
        store.status.averageLevel = 50
        store.adjustVolume(by: -10)
        #expect(store.pendingVolumeLevel == 40)
    }

    @Test("adjustVolume increase is blocked by mismatch")
    func adjustVolumeBlockedByMismatch() {
        var config = AppConfig()
        config.allowForceOnMismatch = false
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        store.status.averageLevel = 50
        store.adjustVolume(by: 5)
        #expect(store.pendingVolumeLevel == nil)
        #expect(store.status.lastError != nil)
    }

    @Test("adjustVolume decrease is allowed despite mismatch")
    func adjustVolumeDownAllowedWithMismatch() {
        var config = AppConfig()
        config.allowForceOnMismatch = false
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        store.status.averageLevel = 50
        store.adjustVolume(by: -5)
        #expect(store.pendingVolumeLevel == 45)
    }

    // MARK: cancelPendingVolume

    @Test("cancelPendingVolume clears pendingVolumeLevel")
    func cancelClearsPending() {
        let store = SpeakerStore.makeForTesting()
        store.pendingVolumeLevel = 60
        store.cancelPendingVolume()
        #expect(store.pendingVolumeLevel == nil)
    }

    @Test("cancelPendingVolume is idempotent when nothing pending")
    func cancelIdempotent() {
        let store = SpeakerStore.makeForTesting()
        store.cancelPendingVolume()
        #expect(store.pendingVolumeLevel == nil)
    }
}
