@testable import KhVolume

@MainActor
final class MockNetworkPathMonitor: NetworkPathMonitor {
    var onPathChange: (@MainActor (Bool) -> Void)?

    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }

    /// Simulate a network path change in tests.
    func simulatePathChange(isSatisfied: Bool) {
        onPathChange?(isSatisfied)
    }
}
