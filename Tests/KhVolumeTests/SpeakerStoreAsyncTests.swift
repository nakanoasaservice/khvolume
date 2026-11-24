import Testing
@testable import KhVolume

@Suite("SpeakerStore — Mute and failed requests", .serialized)
@MainActor
struct SpeakerStoreAsyncTests {
    private let offline = SpeakerError.unreachable(speaker: "Left")

    // MARK: toggleMute

    @Test("toggleMute mutes unmuted speakers")
    func toggleMuteMutes() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        await store.toggleMute()

        #expect(speakers.setMutedArgs == [true])
        #expect(store.isMuted)
    }

    @Test("toggleMute unmutes muted speakers")
    func toggleMuteUnmutes() async {
        let speakers = MockSpeakerGroup()
        speakers.outputs = [.stub(isMuted: true)]
        let store = SpeakerStore.makeForTesting(speakers: speakers, outputs: speakers.outputs)

        await store.toggleMute()

        #expect(speakers.setMutedArgs == [false])
        #expect(!store.isMuted)
    }

    @Test("toggleMute does not block the controls")
    func toggleMuteKeepsConnection() async {
        let store = SpeakerStore.makeForTesting()
        await store.toggleMute()
        #expect(store.connection == .connected)
    }

    @Test("a failed mute marks the connection failed")
    func toggleMuteFailure() async {
        let speakers = MockSpeakerGroup()
        speakers.setMutedError = offline
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        await store.toggleMute()

        #expect(store.connection == .failed(offline))
        #expect(store.outputs.isEmpty)
    }

    @Test("toggleMute while not connected reads the speakers instead of muting")
    func toggleMuteWhileNotConnected() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)
        store.connection = .failed(offline)

        await store.toggleMute()
        await store.settle()

        #expect(speakers.setMutedArgs.isEmpty)
        #expect(speakers.connectCalls.count == 1)
        #expect(store.connection == .connected)
    }

    // MARK: failed level write

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
