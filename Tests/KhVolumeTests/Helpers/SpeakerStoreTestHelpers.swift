import Foundation
@testable import KhVolume

extension SpeakerStore {
    /// Creates a `SpeakerStore` suitable for unit tests.
    ///
    /// Defaults chosen for test isolation:
    /// - Settings are saved to a fresh UserDefaults suite, never the app's own.
    /// - Startup is suppressed and there is no network recovery delay.
    /// - The store starts connected with `outputs`, as after a successful read, so volume changes are sent.
    ///
    /// To test the startup path, pass `suppressStartup: false` directly to `SpeakerStore.init`
    /// and call `store.startupIfNeeded()` explicitly.
    static func makeForTesting(
        config: AppConfig = AppConfig(),
        speakers: (any SpeakerControlling)? = nil,
        outputs: [SpeakerOutput] = [.stub()],
        listInterfaces: @escaping () -> [NetworkInterfaceInfo] = { [] },
        defaults: UserDefaults = .makeForTesting(),
        networkMonitor: MockNetworkMonitorService? = nil,
        hotkeyService: MockHotkeyService? = nil,
        launchAtLoginCoordinator: MockLaunchAtLoginCoordinator? = nil
    ) -> SpeakerStore {
        let store = SpeakerStore(
            config: config,
            speakers: speakers ?? MockSpeakerGroup(),
            listInterfaces: listInterfaces,
            defaults: defaults,
            networkMonitor: networkMonitor,
            hotkeyService: hotkeyService,
            launchAtLoginCoordinator: launchAtLoginCoordinator ?? MockLaunchAtLoginCoordinator()
        )
        store.outputs = outputs
        store.connection = .connected
        return store
    }
}
