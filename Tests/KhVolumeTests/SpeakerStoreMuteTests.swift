import Testing
@testable import KhVolume

@Suite("SpeakerStore — Mute", .serialized)
@MainActor
struct SpeakerStoreMuteTests {
    private let offline = SpeakerError.unreachable(speaker: "Left")

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
}
