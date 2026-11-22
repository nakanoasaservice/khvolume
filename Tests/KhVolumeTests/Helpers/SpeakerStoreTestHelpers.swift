import Foundation
@testable import KhVolume

extension SpeakerStore {
    /// Creates a `SpeakerStore` suitable for unit tests.
    ///
    /// Defaults chosen for test isolation:
    /// - `timing` is `.testing` (all delays zero) so tests run without real sleeps.
    /// - `suppressStartup: true` prevents `startupIfNeeded()` from running automatically.
    /// - The store starts connected, as after a successful refresh, so volume changes are sent.
    ///
    /// To test the startup path, pass `suppressStartup: false` directly to `SpeakerStore.init`
    /// and call `await store.startupIfNeeded()` explicitly.
    static func makeForTesting(
        config: AppConfig = AppConfig(),
        client: any KhvolClientProtocol = MockKhvolClient(),
        networkMonitor: MockNetworkMonitorService? = nil,
        hotkeyService: MockHotkeyService? = nil,
        launchAtLoginCoordinator: MockLaunchAtLoginCoordinator? = nil,
        timing: SpeakerStoreTiming = .testing
    ) -> SpeakerStore {
        let store = SpeakerStore(
            config: config,
            clientFactory: { client },
            networkMonitor: networkMonitor,
            hotkeyService: hotkeyService,
            launchAtLoginCoordinator: launchAtLoginCoordinator,
            timing: timing
        )
        store.connectionState = .ready
        return store
    }
}
