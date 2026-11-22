import Testing
@testable import KhVolume

@Suite("SpeakerStore — Computed Properties")
@MainActor
struct SpeakerStoreComputedTests {

    private func store(maxVolumeLimit: Double = 120, outputs: [SpeakerOutput] = [.stub()]) -> SpeakerStore {
        var config = AppConfig()
        config.maxVolumeLimit = maxVolumeLimit
        return SpeakerStore.makeForTesting(config: config, outputs: outputs)
    }

    // MARK: level

    @Test("level is what the speakers report when nothing was asked for")
    func levelFromOutputs() {
        #expect(store(outputs: [.stub(level: 60)]).level == 60)
    }

    @Test("level is the requested one until the speakers confirm it")
    func levelFromTarget() {
        let store = store(outputs: [.stub(level: 60)])
        store.setLevel(80)
        #expect(store.level == 80)
    }

    // MARK: speakerNamesText

    @Test("speakerNamesText lists the controlled speakers by name")
    func speakerNames() {
        let outputs: [SpeakerOutput] = [.stub(id: "b", name: "Right"), .stub(id: "a", name: "Left")]
        #expect(store(outputs: outputs).speakerNamesText == "Left, Right")
    }

    // MARK: volumeLevelText

    @Test("volumeLevelText is a dash when muted", arguments: [0.0, 50.0, 99.9])
    func volumeLevelTextMuted(level: Double) {
        #expect(store(outputs: [.stub(muted: true)]).volumeLevelText(for: level) == "—")
    }

    @Test("volumeLevelText is a dash when no level is known")
    func volumeLevelTextUnknown() {
        #expect(store(outputs: []).volumeLevelText == "—")
    }

    @Test("volumeLevelText rounds to nearest integer", arguments: [
        (74.4, "74"),
        (74.5, "75"),
        (74.6, "75"),
        (0.0, "0"),
        (120.0, "120"),
    ] as [(Double, String)])
    func volumeLevelTextRounded(level: Double, expected: String) {
        #expect(store().volumeLevelText(for: level) == expected)
    }

    // MARK: volumeFraction

    @Test("volumeFraction at 50% level")
    func volumeFractionHalf() {
        #expect(store(maxVolumeLimit: 100, outputs: [.stub(level: 50)]).volumeFraction == 0.5)
    }

    @Test("volumeFraction clamped to 1.0 when level exceeds max")
    func volumeFractionClamped() {
        #expect(store(maxVolumeLimit: 100, outputs: [.stub(level: 110)]).volumeFraction == 1.0)
    }

    @Test("volumeFraction is 0.0 when muted")
    func volumeFractionMuted() {
        #expect(store(maxVolumeLimit: 100, outputs: [.stub(level: 50, muted: true)]).volumeFraction == 0.0)
    }

    @Test("volumeFraction is 0.0 when effectiveMax is 0 (division guard)")
    func volumeFractionZeroMax() {
        #expect(store(maxVolumeLimit: 0, outputs: [.stub(level: 50)]).volumeFraction == 0.0)
    }

    @Test("volumeFraction uses the requested level")
    func volumeFractionTarget() {
        let store = store(maxVolumeLimit: 100, outputs: [.stub(level: 50)])
        store.setLevel(80)
        #expect(store.volumeFraction == 0.8)
    }

    // MARK: isVolumeSliderDisabled

    @Test("isVolumeSliderDisabled true when muted")
    func sliderDisabledWhenMuted() {
        #expect(store(outputs: [.stub(muted: true)]).isVolumeSliderDisabled)
    }

    @Test("isVolumeSliderDisabled true while searching")
    func sliderDisabledWhileSearching() {
        let store = store()
        store.connection = .searching
        #expect(store.isVolumeSliderDisabled)
    }

    @Test("isVolumeSliderDisabled false when neither muted nor searching")
    func sliderEnabledNormally() {
        #expect(!store().isVolumeSliderDisabled)
    }

    // MARK: blocksVolumeIncrease

    private let unbalanced: [SpeakerOutput] = [.stub(id: "l", level: 60), .stub(id: "r", level: 40)]

    @Test("blocksVolumeIncrease true when unbalanced and force not allowed")
    func blocksIncreaseWhenUnbalanced() {
        #expect(SpeakerStore.makeForTesting(outputs: unbalanced).blocksVolumeIncrease)
    }

    @Test("blocksVolumeIncrease false when unbalanced but force allowed")
    func doesNotBlockWithForceAllowed() {
        var config = AppConfig()
        config.allowForceOnMismatch = true
        #expect(!SpeakerStore.makeForTesting(config: config, outputs: unbalanced).blocksVolumeIncrease)
    }

    @Test("blocksVolumeIncrease false when balanced")
    func doesNotBlockWhenBalanced() {
        #expect(!store().blocksVolumeIncrease)
    }

    // MARK: errorMessage

    @Test("errorMessage describes a failed connection and is nil otherwise")
    func errorMessage() {
        let store = store()
        #expect(store.errorMessage == nil)
        store.connection = .failed(.unreachable(speaker: "Left"))
        #expect(store.errorMessage == "Left is not responding")
    }
}
