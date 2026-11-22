@testable import KhVolume

/// Speakers whose answer to `setLevel` (and, with `suspendsConnect`, to `connect`) arrives only
/// when the test resumes it. Use this to act while a request is in flight.
///
/// Requests are recorded in `calls` in the order they were made. Because both this class and
/// `SpeakerStore` are `@MainActor`, `waitForPending` only has to yield until the store's
/// operation reaches the suspended request.
@MainActor
final class SuspendingSpeakerGroup: SpeakerControlling {
    enum Call: Equatable {
        case connect(rescan: Bool)
        case setLevel(Double)
        case setMuted(Bool)
    }

    typealias Answer = Result<[SpeakerOutput], SpeakerError>

    var suspendsConnect = false
    var connectAnswer: Answer = .success([.stub()])
    var setMutedAnswer: Answer = .success([.stub(muted: true)])

    private(set) var calls: [Call] = []
    private var pending: [CheckedContinuation<Answer, Never>] = []

    var pendingCount: Int { pending.count }

    /// Answers the oldest suspended request.
    func resumeNext(with answer: Answer) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume(returning: answer)
    }

    /// Yields until `count` requests are suspended.
    func waitForPending(_ count: Int = 1) async {
        for _ in 0..<1000 where pending.count < count { await Task.yield() }
    }

    func connect(interface: String?, rescan: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        calls.append(.connect(rescan: rescan))
        return try await (suspendsConnect ? suspend() : connectAnswer).get()
    }

    func setLevel(_ level: Double) async throws(SpeakerError) -> [SpeakerOutput] {
        calls.append(.setLevel(level))
        return try await suspend().get()
    }

    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        calls.append(.setMuted(muted))
        return try setMutedAnswer.get()
    }

    func disconnect() async {}

    private func suspend() async -> Answer {
        await withCheckedContinuation { pending.append($0) }
    }
}
