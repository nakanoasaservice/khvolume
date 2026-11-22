import Testing
@testable import KhVolume

@Suite("SpeakerStore — Volume requests")
@MainActor
struct SpeakerStoreVolumeTests {
    private let unbalanced: [SpeakerOutput] = [.stub(id: "l", level: 60), .stub(id: "r", level: 40)]

    private func forcing() -> AppConfig {
        var config = AppConfig()
        config.allowForceOnMismatch = true
        return config
    }

    // MARK: setLevel — basic

    @Test("setLevel shows the requested level at once")
    func setLevelShowsTarget() {
        let store = SpeakerStore.makeForTesting()
        store.setLevel(75)
        #expect(store.targetLevel == 75)
    }

    @Test("setLevel clamps to effectiveMax")
    func setLevelClampedToMax() {
        var config = AppConfig()
        config.maxVolumeLimit = 100
        let store = SpeakerStore.makeForTesting(config: config)
        store.setLevel(130)
        #expect(store.targetLevel == 100)
    }

    @Test("setLevel clamps to 0")
    func setLevelClampedToZero() {
        let store = SpeakerStore.makeForTesting()
        store.setLevel(-10)
        #expect(store.targetLevel == 0)
    }

    @Test("setLevel is ignored while searching")
    func setLevelIgnoredWhileSearching() {
        let store = SpeakerStore.makeForTesting()
        store.connection = .searching
        store.setLevel(50)
        #expect(store.targetLevel == nil)
    }

    @Test("setLevel sends the level and then shows what the speakers report")
    func setLevelIsSent() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(75)
        await store.settle()

        #expect(speakers.setLevelArgs == [75])
        #expect(store.targetLevel == nil)
        #expect(store.level == 75)
        #expect(store.connection == .connected)
    }

    // MARK: setLevel — unbalanced speakers

    @Test("an unbalanced group shows the quietest speaker's level")
    func unbalancedLevel() {
        #expect(SpeakerStore.makeForTesting(outputs: unbalanced).level == 40)
    }

    @Test("setLevel refuses an increase when unbalanced and force not allowed")
    func setLevelRefusesIncreaseWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.setLevel(41)
        #expect(store.targetLevel == nil)
    }

    @Test("setLevel refuses a level between the speakers, which would raise the quieter one")
    func setLevelRefusesLevelBetweenSpeakers() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.setLevel(50)
        #expect(store.targetLevel == nil)
    }

    @Test("setLevel allows a decrease when unbalanced")
    func setLevelAllowsDecreaseWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.setLevel(39)
        #expect(store.targetLevel == 39)
    }

    @Test("setLevel allows an increase when unbalanced and force allowed")
    func setLevelAllowsIncreaseWithForce() {
        let store = SpeakerStore.makeForTesting(config: forcing(), outputs: unbalanced)
        store.setLevel(70)
        #expect(store.targetLevel == 70)
    }

    // MARK: adjustVolume

    @Test("adjustVolume steps from the reported level")
    func adjustVolumeFromReported() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.adjustVolume(by: 5)
        #expect(store.targetLevel == 55)
    }

    @Test("adjustVolume steps from the requested level when one is waiting")
    func adjustVolumeFromTarget() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.setLevel(60)
        store.adjustVolume(by: 5)
        #expect(store.targetLevel == 65)
    }

    @Test("adjustVolume with negative delta decreases volume")
    func adjustVolumeDown() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.adjustVolume(by: -10)
        #expect(store.targetLevel == 40)
    }

    @Test("adjustVolume up is refused when unbalanced")
    func adjustVolumeUpRefusedWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.adjustVolume(by: 5)
        #expect(store.targetLevel == nil)
    }

    @Test("adjustVolume down when unbalanced goes below the quietest speaker")
    func adjustVolumeDownWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.adjustVolume(by: -5)
        #expect(store.targetLevel == 35)
    }
}
