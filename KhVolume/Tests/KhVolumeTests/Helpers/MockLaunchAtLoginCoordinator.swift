import Observation
@testable import KhVolume

@Observable
@MainActor
final class MockLaunchAtLoginCoordinator: LaunchAtLoginManaging {
    var errorMessage: String?

    private(set) var reconcileCallCount = 0
    private(set) var applyCallCount = 0

    func reconcile(config: inout AppConfig) {
        reconcileCallCount += 1
    }

    func apply(config: inout AppConfig) {
        applyCallCount += 1
    }
}
