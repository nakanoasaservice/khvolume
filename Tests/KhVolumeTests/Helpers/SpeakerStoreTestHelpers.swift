import Foundation
@testable import KhVolume

extension SpeakerStore {
    /// Creates a `SpeakerStore` suitable for unit tests.
    ///
    /// Defaults chosen for test isolation:
    /// - Settings are saved to a fresh UserDefaults suite, never the app's own.
    /// - The store is not started and there is no network recovery delay.
    /// - The store starts connected with `outputs`, as after a successful read, so volume changes are sent.
    ///
    /// To test the startup path, use `SpeakerStore.init` and call `store.start()`.
    static func makeForTesting(
        config: AppConfig = AppConfig(),
        speakers: (any SpeakerControlling)? = nil,
        outputs: [SpeakerOutput] = [.stub()],
        listInterfaces: @escaping () -> [NetworkInterfaceInfo] = { [] },
        defaults: UserDefaults = .makeForTesting(),
        networkMonitor: MockNetworkMonitorService? = nil,
        launchAtLoginCoordinator: MockLaunchAtLoginCoordinator? = nil
    ) -> SpeakerStore {
        let store = SpeakerStore(
            config: config,
            speakers: speakers ?? MockSpeakerGroup(),
            listInterfaces: listInterfaces,
            defaults: defaults,
            networkMonitor: networkMonitor ?? MockNetworkMonitorService(),
            launchAtLoginCoordinator: launchAtLoginCoordinator ?? MockLaunchAtLoginCoordinator(),
            networkRecoveryDelay: .zero
        )
        store.outputs = outputs
        store.connection = .connected
        return store
    }
}
