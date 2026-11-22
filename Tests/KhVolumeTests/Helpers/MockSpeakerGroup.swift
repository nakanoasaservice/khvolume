@testable import KhVolume

/// Speakers that answer at once: sets are applied to `outputs`, like real speakers echo them.
@MainActor
final class MockSpeakerGroup: SpeakerControlling {
    var outputs: [SpeakerOutput] = [.stub()]
    var connectError: SpeakerError?
    var setLevelError: SpeakerError?
    var setMutedError: SpeakerError?

    private(set) var connectCalls: [(interface: String?, rescan: Bool)] = []
    private(set) var setLevelArgs: [Double] = []
    private(set) var setMutedArgs: [Bool] = []
    private(set) var disconnectCallCount = 0

    func connect(interface: String?, rescan: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        connectCalls.append((interface, rescan))
        if let connectError { throw connectError }
        return outputs
    }

    func setLevel(_ level: Double) async throws(SpeakerError) -> [SpeakerOutput] {
        setLevelArgs.append(level)
        if let setLevelError { throw setLevelError }
        for index in outputs.indices { outputs[index].level = level }
        return outputs
    }

    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        setMutedArgs.append(muted)
        if let setMutedError { throw setMutedError }
        for index in outputs.indices { outputs[index].muted = muted }
        return outputs
    }

    func disconnect() async {
        disconnectCallCount += 1
    }
}

extension SpeakerOutput {
    static func stub(
        id: String = "speaker",
        name: String = "Speaker",
        level: Double = 50,
        muted: Bool = false
    ) -> SpeakerOutput {
        SpeakerOutput(id: id, name: name, level: level, muted: muted)
    }
}
