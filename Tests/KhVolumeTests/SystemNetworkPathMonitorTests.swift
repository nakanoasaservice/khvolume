import Testing
@testable import KhVolume

@Suite("SystemNetworkPathMonitor")
@MainActor
struct SystemNetworkPathMonitorTests {

    /// NWPathMonitor reports the current path once when it starts. Treating that as a change made
    /// the store close the connections it had just opened at launch.
    @Test("starting does not report the current path as a change")
    func startIsNotAChange() async throws {
        let monitor = SystemNetworkPathMonitor()
        var changes = 0
        monitor.onPathChange = { _ in changes += 1 }

        monitor.start()
        try await Task.sleep(for: .milliseconds(500))
        monitor.stop()

        #expect(changes == 0)
    }
}
