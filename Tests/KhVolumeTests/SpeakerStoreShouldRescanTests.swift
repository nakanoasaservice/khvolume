import Testing
@testable import KhVolume

@Suite("SpeakerStore — rescan when no speakers are stored")
@MainActor
struct SpeakerStoreShouldRescanTests {

    @Test("refresh rescans when no speakers are configured")
    func rescansWithoutSpeakers() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .failure(.noSpeakers)
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(mock.scanCallCount == 1)
    }

    @Test("refresh does not rescan after other errors", arguments: [
        KhvolError.deviceError("Left: unexpected reply"),
        KhvolError.commandFailed("device fe80::1 is not online"),
    ])
    func noRescanAfterOtherErrors(error: KhvolError) async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .failure(error)
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(mock.scanCallCount == 0)
    }
}
