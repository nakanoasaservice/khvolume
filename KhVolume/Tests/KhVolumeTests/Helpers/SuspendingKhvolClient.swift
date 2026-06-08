@testable import KhVolume

/// A `KhvolClientProtocol` mock whose `setLevel` suspends until the test explicitly
/// resumes it. Use this to reproduce concurrency scenarios such as stale commit
/// results arriving after a newer preview has already been committed.
///
/// ## How it works
///
/// Each call to `setLevel` stores a `CheckedContinuation` in `pendingCommits` and
/// suspends. The test controls when each in-flight request "returns" by calling
/// `resumeNext(with:)`. Because `SpeakerStore` is `@MainActor`, a single
/// `await Task.yield()` in the test is enough to advance a task to its first
/// suspension point (`setLevel`), making the sequencing deterministic.
@MainActor
final class SuspendingKhvolClient: KhvolClientProtocol, @unchecked Sendable {

    // MARK: - Controllable setLevel

    struct PendingCommit {
        let level: Double
        fileprivate let continuation: CheckedContinuation<KhvolJSONStatus, any Error>
    }

    private(set) var pendingCommits: [PendingCommit] = []
    private(set) var setLevelCallCount = 0

    func setLevel(_ level: Double) async throws -> KhvolJSONStatus {
        setLevelCallCount += 1
        return try await withCheckedThrowingContinuation { cont in
            pendingCommits.append(PendingCommit(level: level, continuation: cont))
        }
    }

    /// Resume the oldest pending `setLevel` call with `result`.
    func resumeNext(with result: Result<KhvolJSONStatus, any Error>) {
        guard !pendingCommits.isEmpty else { return }
        let commit = pendingCommits.removeFirst()
        switch result {
        case .success(let json): commit.continuation.resume(returning: json)
        case .failure(let err): commit.continuation.resume(throwing: err)
        }
    }

    // MARK: - Immediate-return methods (configurable)

    var jsonStatusResult: Result<KhvolJSONStatus, Error> = .success(.stub())
    var setMutedResult:   Result<KhvolJSONStatus, Error> = .success(.stub())
    var interfacesResult: Result<[NetworkInterfaceInfo], Error> = .success([])
    var scanResult:       Result<Int, Error> = .success(1)
    private(set) var jsonStatusCallCount = 0

    func jsonStatus() async throws -> KhvolJSONStatus {
        jsonStatusCallCount += 1
        return try jsonStatusResult.get()
    }

    func setMuted(_ muted: Bool) async throws -> KhvolJSONStatus {
        try setMutedResult.get()
    }

    func interfaces() async throws -> [NetworkInterfaceInfo] {
        try interfacesResult.get()
    }

    func scan() async throws -> Int {
        try scanResult.get()
    }
}
