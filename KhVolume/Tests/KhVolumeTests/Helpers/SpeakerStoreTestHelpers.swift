import Foundation
@testable import KhVolume

extension SpeakerStore {
    /// Creates a `SpeakerStore` suitable for unit tests.
    ///
    /// Defaults chosen for test isolation:
    /// - `hasSpeakerCache` returns `true` so `shouldRescan` tests only exercise message matching.
    /// - `timing` is `.testing` (all delays zero) so tests run without real sleeps.
    /// - `suppressStartup: true` prevents `startupIfNeeded()` from running automatically.
    ///
    /// To test the startup path, pass `suppressStartup: false` directly to `SpeakerStore.init`
    /// and call `await store.startupIfNeeded()` explicitly.
    static func makeForTesting(
        config: AppConfig = AppConfig(),
        client: MockKhvolClient = MockKhvolClient(),
        networkMonitor: MockNetworkMonitorService? = nil,
        hotkeyService: MockHotkeyService? = nil,
        launchAtLoginCoordinator: MockLaunchAtLoginCoordinator? = nil,
        hasSpeakerCache: @escaping () -> Bool = { true },
        now: @escaping () -> Date = { Date() },
        timing: SpeakerStoreTiming = .testing
    ) -> SpeakerStore {
        SpeakerStore(
            config: config,
            clientFactory: { client },
            networkMonitor: networkMonitor,
            hotkeyService: hotkeyService,
            launchAtLoginCoordinator: launchAtLoginCoordinator,
            hasSpeakerCache: hasSpeakerCache,
            now: now,
            timing: timing
        )
    }

    /// Awaits the current `volumeCommitTask` to completion.
    /// Use after `setVolumePreview(_:)` in tests to synchronise with the commit task.
    func awaitVolumeCommit() async {
        await volumeCommitTask?.value
    }
}
