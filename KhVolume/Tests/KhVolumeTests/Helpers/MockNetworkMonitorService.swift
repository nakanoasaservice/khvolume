@testable import KhVolume

@MainActor
final class MockNetworkMonitorService: NetworkMonitorService {
    var onPathChange: (@MainActor (Bool) -> Void)?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    /// Simulate a network path change in tests.
    func simulatePathChange(isSatisfied: Bool) {
        onPathChange?(isSatisfied)
    }
}
