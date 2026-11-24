import Testing
@testable import KhVolume

@Suite("SpeakerStore — Computed Properties")
@MainActor
struct SpeakerStoreComputedTests {

    private func store(levelLimit: Double = 120, outputs: [SpeakerOutput] = [.stub()]) -> SpeakerStore {
        var config = AppConfig()
        config.levelLimit = levelLimit
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

    // MARK: levelText

    @Test("levelText is a dash when muted", arguments: [0.0, 50.0, 99.9])
    func levelTextMuted(level: Double) {
        #expect(store(outputs: [.stub(isMuted: true)]).levelText(for: level) == "—")
    }

    @Test("levelText is a dash when no level is known")
    func levelTextUnknown() {
        #expect(store(outputs: []).levelText == "—")
    }

    @Test("levelText rounds to nearest integer", arguments: [
        (74.4, "74"),
        (74.5, "75"),
        (74.6, "75"),
        (0.0, "0"),
        (120.0, "120"),
    ] as [(Double, String)])
    func levelTextRounded(level: Double, expected: String) {
        #expect(store().levelText(for: level) == expected)
    }

    // MARK: levelFraction

    @Test("levelFraction at 50% level")
    func levelFractionHalf() {
        #expect(store(levelLimit: 100, outputs: [.stub(level: 50)]).levelFraction == 0.5)
    }

    @Test("levelFraction clamped to 1.0 when level exceeds max")
    func levelFractionClamped() {
        #expect(store(levelLimit: 100, outputs: [.stub(level: 110)]).levelFraction == 1.0)
    }

    @Test("levelFraction is 0.0 when muted")
    func levelFractionMuted() {
        #expect(store(levelLimit: 100, outputs: [.stub(level: 50, isMuted: true)]).levelFraction == 0.0)
    }

    @Test("levelFraction is 0.0 when maxLevel is 0 (division guard)")
    func levelFractionZeroMax() {
        #expect(store(levelLimit: 0, outputs: [.stub(level: 50)]).levelFraction == 0.0)
    }

    @Test("levelFraction uses the requested level")
    func levelFractionTarget() {
        let store = store(levelLimit: 100, outputs: [.stub(level: 50)])
        store.setLevel(80)
        #expect(store.levelFraction == 0.8)
    }

    // MARK: isVolumeSliderDisabled

    @Test("isVolumeSliderDisabled true when muted")
    func sliderDisabledWhenMuted() {
        #expect(store(outputs: [.stub(isMuted: true)]).isVolumeSliderDisabled)
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

    // MARK: blocksLevelIncrease

    private let unbalanced: [SpeakerOutput] = [.stub(id: "l", level: 60), .stub(id: "r", level: 40)]

    @Test("blocksLevelIncrease true when unbalanced and force not allowed")
    func blocksIncreaseWhenUnbalanced() {
        #expect(SpeakerStore.makeForTesting(outputs: unbalanced).blocksLevelIncrease)
    }

    @Test("blocksLevelIncrease false when unbalanced but force allowed")
    func doesNotBlockWithForceAllowed() {
        var config = AppConfig()
        config.allowsIncreaseWhileUnbalanced = true
        #expect(!SpeakerStore.makeForTesting(config: config, outputs: unbalanced).blocksLevelIncrease)
    }

    @Test("blocksLevelIncrease false when balanced")
    func doesNotBlockWhenBalanced() {
        #expect(!store().blocksLevelIncrease)
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
