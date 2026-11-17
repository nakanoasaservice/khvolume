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
        fileprivate let continuation: CheckedContinuation<Result<KhvolJSONStatus, KhvolError>, Never>
    }

    private(set) var pendingCommits: [PendingCommit] = []
    private(set) var setLevelCallCount = 0

    func setLevel(_ level: Double) async throws(KhvolError) -> KhvolJSONStatus {
        setLevelCallCount += 1
        let result: Result<KhvolJSONStatus, KhvolError> = await withCheckedContinuation { cont in
            pendingCommits.append(PendingCommit(level: level, continuation: cont))
        }
        switch result {
        case .success(let json): return json
        case .failure(let error): throw error
        }
    }

    /// Resume the oldest pending `setLevel` call with `result`.
    func resumeNext(with result: Result<KhvolJSONStatus, KhvolError>) {
        guard !pendingCommits.isEmpty else { return }
        let commit = pendingCommits.removeFirst()
        commit.continuation.resume(returning: result)
    }

    // MARK: - Immediate-return methods (configurable)

    var jsonStatusResult: Result<KhvolJSONStatus, KhvolError> = .success(.stub())
    var setMutedResult:   Result<KhvolJSONStatus, KhvolError> = .success(.stub())
    var interfacesResult: Result<[NetworkInterfaceInfo], KhvolError> = .success([])
    var scanResult:       Result<Int, KhvolError> = .success(1)
    private(set) var jsonStatusCallCount = 0

    func jsonStatus() async throws(KhvolError) -> KhvolJSONStatus {
        jsonStatusCallCount += 1
        return try jsonStatusResult.get()
    }

    func setMuted(_ muted: Bool) async throws(KhvolError) -> KhvolJSONStatus {
        try setMutedResult.get()
    }

    func interfaces() async throws(KhvolError) -> [NetworkInterfaceInfo] {
        try interfacesResult.get()
    }

    func scan() async throws(KhvolError) -> Int {
        try scanResult.get()
    }
}
