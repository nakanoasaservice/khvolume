import Foundation
import Testing
@testable import KhVolume

@Suite("SpeakerStore — Connection", .serialized)
@MainActor
struct SpeakerStoreConnectionTests {
    private let offline = SpeakerError.unreachable(speaker: "Left")

    private func configured(_ interface: String? = "en15") -> AppConfig {
        var config = AppConfig()
        config.networkInterface = interface
        return config
    }

    // MARK: startup

    @Test("startup registers hotkeys, watches the network and reads the speakers")
    func startup() async {
        let speakers = MockSpeakerGroup()
        speakers.outputs = [.stub(level: 62)]
        let monitor = MockNetworkMonitorService()
        let hotkeys = MockHotkeyService()
        let launchAtLogin = MockLaunchAtLoginCoordinator()
        let store = SpeakerStore(
            config: configured(),
            speakers: speakers,
            listInterfaces: { [NetworkInterfaceInfo(name: "en15", label: "USB LAN", isActive: true)] },
            defaults: .makeForTesting(),
            networkMonitor: monitor,
            hotkeyService: hotkeys,
            launchAtLoginCoordinator: launchAtLogin,
            suppressStartup: false
        )

        store.startupIfNeeded()
        #expect(store.connection == .searching)
        await store.settle()

        #expect(hotkeys.registerCallCount == 1)
        #expect(monitor.startCallCount == 1)
        #expect(launchAtLogin.reconcileCallCount == 1)
        #expect(store.interfaces.map(\.name) == ["en15"])
        #expect(speakers.connectCalls.map(\.interface) == ["en15"])
        #expect(speakers.connectCalls.map(\.rescan) == [false])
        #expect(store.connection == .connected)
        #expect(store.level == 62)
    }

    // MARK: refresh

    @Test("refresh shows what the speakers report")
    func refreshSuccess() async {
        let speakers = MockSpeakerGroup()
        speakers.outputs = [.stub(level: 80)]
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.refresh()
        #expect(store.connection == .connected)  // re-reading does not block the controls
        await store.settle()

        #expect(store.level == 80)
        #expect(store.connection == .connected)
    }

    @Test("a failed refresh marks the connection failed and forgets the outputs")
    func refreshFailure() async {
        let speakers = MockSpeakerGroup()
        speakers.connectError = offline
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.refresh()
        await store.settle()

        #expect(store.connection == .failed(offline))
        #expect(store.outputs.isEmpty)
    }

    @Test("refreshes asked for while one is waiting are one read")
    func refreshIsCoalesced() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        store.refresh()
        store.refresh()
        store.preparePopover()
        await store.settle()

        #expect(speakers.connectCalls.count == 1)
    }

    @Test("a retry after a failure keeps showing the failure until it succeeds")
    func retryAfterFailure() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(speakers: speakers)
        store.connection = .failed(offline)

        store.refresh()
        #expect(store.connection == .failed(offline))
        await store.settle()

        #expect(store.connection == .connected)
    }

    @Test("a missing interface is reported as a failure")
    func noInterface() async {
        let speakers = MockSpeakerGroup()
        speakers.connectError = .noInterface
        let store = SpeakerStore.makeForTesting(config: configured(nil), speakers: speakers)

        store.refresh()
        await store.settle()

        #expect(speakers.connectCalls.map(\.interface) == [nil])
        #expect(store.errorMessage == "No network interface selected")
    }

    // MARK: selectInterface

    @Test("selectInterface saves the interface and searches for speakers on it")
    func selectInterface() async {
        let speakers = MockSpeakerGroup()
        speakers.outputs = [.stub(level: 44)]
        let defaults = UserDefaults.makeForTesting()
        let store = SpeakerStore.makeForTesting(config: configured("en0"), speakers: speakers, defaults: defaults)

        await store.selectInterface("en15")

        #expect(store.config.networkInterface == "en15")
        #expect(AppDefaults.loadConfig(from: defaults).networkInterface == "en15")
        #expect(speakers.connectCalls.map(\.interface) == ["en15"])
        #expect(speakers.connectCalls.map(\.rescan) == [true])
        #expect(store.connection == .connected)
        #expect(store.level == 44)
    }

    @Test("selectInterface reports when no speakers are found")
    func selectInterfaceFindsNothing() async {
        let speakers = MockSpeakerGroup()
        speakers.connectError = .noSpeakersFound(interface: "en15")
        let store = SpeakerStore.makeForTesting(speakers: speakers)

        await store.selectInterface("en15")

        #expect(store.connection == .failed(.noSpeakersFound(interface: "en15")))
    }

    @Test("selectInterface is ignored while searching")
    func selectInterfaceWhileSearching() async {
        let speakers = MockSpeakerGroup()
        let store = SpeakerStore.makeForTesting(config: configured("en0"), speakers: speakers)
        store.connection = .searching

        await store.selectInterface("en15")

        #expect(store.config.networkInterface == "en0")
        #expect(speakers.connectCalls.isEmpty)
    }

    // MARK: network changes

    private func startedStore(
        speakers: MockSpeakerGroup, monitor: MockNetworkMonitorService, interfaces: [NetworkInterfaceInfo]
    ) async -> SpeakerStore {
        let store = SpeakerStore(
            config: configured(),
            speakers: speakers,
            listInterfaces: { interfaces },
            defaults: .makeForTesting(),
            networkMonitor: monitor,
            hotkeyService: MockHotkeyService(),
            launchAtLoginCoordinator: MockLaunchAtLoginCoordinator(),
            suppressStartup: false
        )
        store.startupIfNeeded()
        await store.settle()
        return store
    }

    /// Lets the tasks a network change starts (disconnect, debounced recovery) run.
    private func drainNetworkTasks(_ store: SpeakerStore) async {
        for _ in 0..<50 { await Task.yield() }
        await store.settle()
    }

    private let lan = [NetworkInterfaceInfo(name: "en15", label: "USB LAN", isActive: true)]

    @Test("a network change drops the connections")
    func networkChangeDisconnects() async {
        let speakers = MockSpeakerGroup()
        let monitor = MockNetworkMonitorService()
        let store = await startedStore(speakers: speakers, monitor: monitor, interfaces: lan)

        monitor.simulatePathChange(isSatisfied: false)
        await drainNetworkTasks(store)

        #expect(speakers.disconnectCallCount == 1)
        #expect(speakers.connectCalls.count == 1)  // only the startup read
    }

    @Test("a restored network reconnects when the connection had failed")
    func networkRestoredReconnects() async {
        let speakers = MockSpeakerGroup()
        speakers.connectError = offline
        let monitor = MockNetworkMonitorService()
        let store = await startedStore(speakers: speakers, monitor: monitor, interfaces: lan)
        #expect(store.connection == .failed(offline))

        speakers.connectError = nil
        monitor.simulatePathChange(isSatisfied: true)
        await drainNetworkTasks(store)

        #expect(store.connection == .connected)
    }

    @Test("a restored network leaves a working connection alone")
    func networkRestoredWhileConnected() async {
        let speakers = MockSpeakerGroup()
        let monitor = MockNetworkMonitorService()
        let store = await startedStore(speakers: speakers, monitor: monitor, interfaces: lan)

        monitor.simulatePathChange(isSatisfied: true)
        await drainNetworkTasks(store)

        #expect(speakers.connectCalls.count == 1)
    }
}

@Suite("SystemNetworkMonitorService")
@MainActor
struct SystemNetworkMonitorServiceTests {

    /// NWPathMonitor reports the current path once when it starts. Treating that as a change made
    /// the store close the connections it had just opened at launch.
    @Test("starting does not report the current path as a change")
    func startIsNotAChange() async throws {
        let monitor = SystemNetworkMonitorService()
        var changes = 0
        monitor.onPathChange = { _ in changes += 1 }

        monitor.start()
        try await Task.sleep(for: .milliseconds(500))
        monitor.stop()

        #expect(changes == 0)
    }
}
