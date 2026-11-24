import Testing
@testable import KhVolume

@Suite("SpeakerStore — Volume requests", .serialized)
@MainActor
struct SpeakerStoreVolumeTests {
    private let offline = SpeakerError.unreachable(speaker: "Left")
    private let unbalanced: [SpeakerOutput] = [.stub(id: "l", level: 60), .stub(id: "r", level: 40)]

    private func forcing() -> AppConfig {
        var config = AppConfig()
        config.allowsIncreaseWhileUnbalanced = true
        return config
    }

    // MARK: setLevel — basic

    @Test("setLevel shows the requested level at once")
    func setLevelShowsTarget() {
        let store = SpeakerStore.makeForTesting()
        store.setLevel(75)
        #expect(store.targetLevel == 75)
    }

    @Test("setLevel clamps to maxLevel")
    func setLevelClampedToMax() {
        var config = AppConfig()
        config.levelLimit = 100
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

    // MARK: adjustLevel

    @Test("adjustLevel steps from the reported level")
    func adjustLevelFromReported() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.adjustLevel(by: 5)
        #expect(store.targetLevel == 55)
    }

    @Test("adjustLevel steps from the requested level when one is waiting")
    func adjustLevelFromTarget() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.setLevel(60)
        store.adjustLevel(by: 5)
        #expect(store.targetLevel == 65)
    }

    @Test("adjustLevel with negative delta decreases volume")
    func adjustLevelDown() {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        store.adjustLevel(by: -10)
        #expect(store.targetLevel == 40)
    }

    @Test("adjustLevel up is refused when unbalanced")
    func adjustLevelUpRefusedWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.adjustLevel(by: 5)
        #expect(store.targetLevel == nil)
    }

    @Test("adjustLevel down when unbalanced goes below the quietest speaker")
    func adjustLevelDownWhenUnbalanced() {
        let store = SpeakerStore.makeForTesting(outputs: unbalanced)
        store.adjustLevel(by: -5)
        #expect(store.targetLevel == 35)
    }

    // MARK: failed requests

    @Test("a failed level write drops the level and marks the connection failed")
    func setLevelFailure() async {
        let speakers = MockSpeakerGroup()
        speakers.setLevelError = offline
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(75)
        await store.settle()

        #expect(store.targetLevel == nil)
        #expect(store.connection == .failed(offline))
        #expect(store.errorMessage == "Left is not responding")
        #expect(store.outputs.isEmpty)
    }

    @Test("opening the popover reads the speakers again after a failed write")
    func popoverRecoversAfterFailedWrite() async {
        let speakers = MockSpeakerGroup()
        speakers.setLevelError = offline
        let store = SpeakerStore.makeForTesting(speakers: speakers)
        store.setLevel(75)
        await store.settle()

        speakers.outputs = [.stub(level: 60)]
        store.preparePopover()
        await store.settle()

        #expect(store.level == 60)
        #expect(store.connection == .connected)
    }

    @Test("a volume change while not connected reads the speakers instead of sending a level")
    func volumeChangeWhileNotConnected() async {
        let speakers = MockSpeakerGroup()
        speakers.outputs = [.stub(level: 60)]
        let store = SpeakerStore.makeForTesting(speakers: speakers, outputs: [])
        store.connection = .failed(offline)

        store.adjustLevel(by: 1)
        await store.settle()

        #expect(speakers.setLevelArgs.isEmpty)
        #expect(store.level == 60)
        #expect(store.connection == .connected)
    }
}
