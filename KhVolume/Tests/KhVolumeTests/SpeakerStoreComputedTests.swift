import Testing
@testable import KhVolume

@Suite("SpeakerStore — Computed Properties")
@MainActor
struct SpeakerStoreComputedTests {

    // MARK: previewAverageLevel

    @Test("previewAverageLevel falls back to status.averageLevel when no pending")
    func previewAverageLevelNoPending() {
        let store = SpeakerStore.makeForTesting()
        store.status.averageLevel = 60
        #expect(store.previewAverageLevel == 60)
    }

    @Test("previewAverageLevel returns pendingVolumeLevel when set")
    func previewAverageLevelPending() {
        let store = SpeakerStore.makeForTesting()
        store.status.averageLevel = 60
        store.pendingVolumeLevel = 80
        #expect(store.previewAverageLevel == 80)
    }

    // MARK: volumeLevelText

    @Test("volumeLevelText returns em-dash when muted", arguments: [0.0, 50.0, 99.9])
    func volumeLevelTextMuted(level: Double) {
        let store = SpeakerStore.makeForTesting()
        store.status.isMuted = true
        #expect(store.volumeLevelText(for: level) == "—")
    }

    @Test("volumeLevelText rounds to nearest integer", arguments: [
        (74.4, "74"),
        (74.5, "75"),
        (74.6, "75"),
        (0.0, "0"),
        (120.0, "120"),
    ] as [(Double, String)])
    func volumeLevelTextRounded(level: Double, expected: String) {
        let store = SpeakerStore.makeForTesting()
        store.status.isMuted = false
        #expect(store.volumeLevelText(for: level) == expected)
    }

    // MARK: volumeFraction

    @Test("volumeFraction at 50% level")
    func volumeFractionHalf() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.averageLevel = 50
        #expect(store.volumeFraction == 0.5)
    }

    @Test("volumeFraction clamped to 1.0 when level exceeds max")
    func volumeFractionClamped() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.averageLevel = 110
        #expect(store.volumeFraction == 1.0)
    }

    @Test("volumeFraction is 0.0 when muted")
    func volumeFractionMuted() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.averageLevel = 50
        store.status.isMuted = true
        #expect(store.volumeFraction == 0.0)
    }

    @Test("volumeFraction is 0.0 when effectiveMax is 0 (division guard)")
    func volumeFractionZeroMax() {
        var config = AppConfig()
        config.maxVolumeLimit = 0
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.averageLevel = 50
        #expect(store.volumeFraction == 0.0)
    }

    @Test("volumeFraction uses pendingVolumeLevel when set")
    func volumeFractionPending() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.averageLevel = 50
        store.pendingVolumeLevel = 80
        #expect(store.volumeFraction == 0.8)
    }

    // MARK: isVolumeSliderDisabled

    @Test("isVolumeSliderDisabled true when muted")
    func sliderDisabledWhenMuted() {
        let store = SpeakerStore.makeForTesting()
        store.status.isMuted = true
        #expect(store.isVolumeSliderDisabled == true)
    }

    @Test("isVolumeSliderDisabled true when isStatusLoading")
    func sliderDisabledWhenLoading() {
        let store = SpeakerStore.makeForTesting()
        store.isStatusLoading = true
        #expect(store.isVolumeSliderDisabled == true)
    }

    @Test("isVolumeSliderDisabled false when neither muted nor loading")
    func sliderEnabledNormally() {
        let store = SpeakerStore.makeForTesting()
        store.status.isMuted = false
        store.isStatusLoading = false
        #expect(store.isVolumeSliderDisabled == false)
    }

    // MARK: blocksVolumeIncrease

    @Test("blocksVolumeIncrease true when mismatch and force not allowed")
    func blocksIncreaseWithMismatch() {
        var config = AppConfig()
        config.allowForceOnMismatch = false
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        #expect(store.blocksVolumeIncrease == true)
    }

    @Test("blocksVolumeIncrease false when mismatch but force allowed")
    func doesNotBlockWithForceAllowed() {
        var config = AppConfig()
        config.allowForceOnMismatch = true
        let store = SpeakerStore.makeForTesting(config: config)
        store.status.levelMismatch = true
        #expect(store.blocksVolumeIncrease == false)
    }

    @Test("blocksVolumeIncrease false when no mismatch")
    func doesNotBlockWithoutMismatch() {
        let store = SpeakerStore.makeForTesting()
        store.status.levelMismatch = false
        #expect(store.blocksVolumeIncrease == false)
    }
}
