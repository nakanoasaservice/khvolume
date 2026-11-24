import Testing
@testable import KhVolume

/// What happens to requests made while the speakers are still answering an earlier one.
@Suite("SpeakerStore — Requests in flight", .serialized)
@MainActor
struct SpeakerStoreVolumeConcurrencyTests {
    private let offline = SpeakerError.unreachable(speaker: "Left")

    @Test("levels asked for before the first is sent are one request for the last")
    func rapidLevelsSendOnlyTheLast() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        store.setLevel(75)
        store.setLevel(80)
        await store.settle()

        #expect(speakers.setLevelArgs == [80])
        #expect(store.targetLevel == nil)
        #expect(store.level == 80)
    }

    @Test("levels asked for during a request are one following request for the last")
    func levelsDuringRequestAreCoalesced() async {
        let speakers = SuspendingSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        store.setLevel(75)
        store.setLevel(80)
        #expect(speakers.calls == [.setLevel(70)])  // one request at a time

        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await speakers.waitForPending()
        #expect(speakers.calls == [.setLevel(70), .setLevel(80)])
        #expect(store.level == 80)  // still the requested level, not the confirmed 70

        speakers.resumeNext(with: .success([.stub(level: 80)]))
        await store.settle()

        #expect(speakers.calls == [.setLevel(70), .setLevel(80)])
        #expect(store.targetLevel == nil)
        #expect(store.outputs == [.stub(level: 80)])
    }

    @Test("the same level asked for again during its request is not sent twice")
    func sameLevelIsNotResent() async {
        let speakers = SuspendingSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        store.setLevel(70)
        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await store.settle()

        #expect(speakers.calls == [.setLevel(70)])
    }

    @Test("a failed request drops the levels asked for during it")
    func failureDropsWaitingLevel() async {
        let speakers = SuspendingSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        store.setLevel(80)
        speakers.resumeNext(with: .failure(offline))
        await store.settle()

        #expect(speakers.calls == [.setLevel(70)])
        #expect(store.targetLevel == nil)
        #expect(store.connection == .failed(offline))
    }

    @Test("a level can be requested again after the previous requests finished")
    func writesAgainAfterFinishing() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await store.settle()
        store.setLevel(60)
        await store.settle()

        #expect(speakers.setLevelArgs == [70, 60])
    }

    @Test("refresh is skipped while a level is being written")
    func refreshSkippedWhileWriting() async {
        let speakers = SuspendingSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        store.preparePopover()
        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await store.settle()

        #expect(speakers.calls == [.setLevel(70)])
    }

    @Test("a level asked for during a read is sent after it and wins")
    func levelDuringReadIsSentAfterIt() async {
        let speakers = SuspendingSpeakerGroup()
        speakers.suspendsConnect = true
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.refresh()
        await speakers.waitForPending()
        store.setLevel(70)
        for _ in 0..<50 { await Task.yield() }
        #expect(speakers.calls == [.connect(rescan: false)])  // the write waits for the read

        speakers.resumeNext(with: .success([.stub(level: 50)]))
        await speakers.waitForPending()
        #expect(store.level == 70)
        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await store.settle()

        #expect(speakers.calls == [.connect(rescan: false), .setLevel(70)])
        #expect(store.outputs == [.stub(level: 70)])
    }

    @Test("a level asked for during a read that fails is not sent")
    func levelDuringFailedReadIsDropped() async {
        let speakers = SuspendingSpeakerGroup()
        speakers.suspendsConnect = true
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.refresh()
        await speakers.waitForPending()
        store.setLevel(70)
        speakers.resumeNext(with: .failure(offline))
        await store.settle()

        #expect(speakers.calls == [.connect(rescan: false)])
        #expect(store.targetLevel == nil)
        #expect(store.connection == .failed(offline))
    }

    @Test("mute during a level request is sent after it")
    func muteWaitsForLevelRequest() async {
        let speakers = SuspendingSpeakerGroup()
        speakers.setMutedAnswer = .success([.stub(level: 70, isMuted: true)])
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        let mute = Task { await store.toggleMute() }
        for _ in 0..<50 { await Task.yield() }
        #expect(speakers.calls == [.setLevel(70)])

        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await mute.value

        #expect(speakers.calls == [.setLevel(70), .setMuted(true)])
        #expect(store.outputs == [.stub(level: 70, isMuted: true)])
    }

    @Test("selecting an interface drops a level that was waiting to be sent")
    func selectInterfaceDropsWaitingLevel() async {
        let speakers = SuspendingSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.setLevel(70)
        await speakers.waitForPending()
        store.setLevel(80)
        let select = Task { await store.selectInterface("en15") }
        for _ in 0..<50 { await Task.yield() }
        speakers.resumeNext(with: .success([.stub(level: 70)]))
        await select.value

        #expect(speakers.calls == [.setLevel(70), .connect(rescan: true)])
        #expect(store.connection == .connected)
    }
}
