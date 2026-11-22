import AppKit
import Observation

/// The app's state: settings, what the speakers report, and what the user asked of them.
@Observable
@MainActor
final class SpeakerStore {
    var config: AppConfig
    var interfaces: [NetworkInterfaceInfo] = []
    /// What the speakers last reported; empty while nothing is known.
    /// Not `private(set)` so tests can start from a known state, like `connection`.
    var outputs: [SpeakerOutput] = []
    var connection: ConnectionState = .disconnected
    /// The level the user asked for, until the speakers have confirmed it.
    private(set) var targetLevel: Double?

    /// Forwarded from `launchAtLoginCoordinator.errorMessage`.
    var launchAtLoginMessage: String? { launchAtLoginCoordinator.errorMessage }

    /// Manages LaunchAtLogin preference and owns its error-message state.
    let launchAtLoginCoordinator: any LaunchAtLoginManaging

    private let speakers: any SpeakerControlling
    private let listInterfaces: () -> [NetworkInterfaceInfo]
    private let defaults: UserDefaults
    /// Debounce applied after a network path change before attempting recovery.
    private let networkRecoveryDelay: Duration
    /// Retained HotkeyService instance (production: HotkeyManager; tests: mock).
    private var hotkeyService: (any HotkeyService)?
    private var networkMonitor: (any NetworkMonitorService)?
    private var networkRecoveryTask: Task<Void, Never>?
    private var hasStartedUp = false

    /// The speaker operation queued last; each one waits for the one before it.
    private var lastOperation: Task<Void, Never>?
    private var isWriting = false
    private var isRefreshing = false

    init() {
        config = AppDefaults.loadConfig()
        speakers = SpeakerGroup()
        listInterfaces = NetworkInterfaceLister.list
        defaults = .standard
        networkRecoveryDelay = .milliseconds(500)
        launchAtLoginCoordinator = LaunchAtLoginCoordinator()
        // Start here, not from a view, so volume and hotkeys work before the popover is opened.
        Task { startupIfNeeded() }
    }

    /// Testing initializer — all infrastructure dependencies are injectable.
    ///
    /// - Parameters:
    ///   - suppressStartup: When `true` (the default), `startupIfNeeded()` is a no-op.
    ///     Pass `false` and call `startupIfNeeded()` explicitly to test the startup path.
    init(
        config: AppConfig,
        speakers: any SpeakerControlling,
        listInterfaces: @escaping () -> [NetworkInterfaceInfo] = { [] },
        defaults: UserDefaults,
        networkMonitor: (any NetworkMonitorService)? = nil,
        hotkeyService: (any HotkeyService)? = nil,
        launchAtLoginCoordinator: (any LaunchAtLoginManaging)? = nil,
        networkRecoveryDelay: Duration = .zero,
        suppressStartup: Bool = true
    ) {
        self.config = config
        self.speakers = speakers
        self.listInterfaces = listInterfaces
        self.defaults = defaults
        self.networkMonitor = networkMonitor
        self.hotkeyService = hotkeyService
        self.launchAtLoginCoordinator = launchAtLoginCoordinator ?? LaunchAtLoginCoordinator()
        self.networkRecoveryDelay = networkRecoveryDelay
        if suppressStartup { self.hasStartedUp = true }
    }

    // MARK: - Startup

    /// Called at launch so volume and hotkeys work without opening the menu bar popover.
    func startupIfNeeded() {
        guard !hasStartedUp else { return }
        hasStartedUp = true

        if hotkeyService == nil {
            hotkeyService = HotkeyManager(store: self)
        }
        hotkeyService?.register()

        launchAtLoginCoordinator.reconcile(config: &config)
        setupNetworkMonitor()
        observeSleep()
        loadInterfaces()
        refresh()
    }

    // MARK: - Derived state

    /// The level every volume control shows: the requested one until the speakers confirm it.
    var level: Double { targetLevel ?? outputs.level }
    var isMuted: Bool { outputs.isMuted }
    var isBalanced: Bool { outputs.isBalanced }
    var isSearching: Bool { connection == .searching }

    var blocksVolumeIncrease: Bool {
        !isBalanced && !config.allowForceOnMismatch
    }

    var errorMessage: String? {
        if case .failed(let error) = connection { error.errorDescription } else { nil }
    }

    // MARK: - Config persistence

    func saveConfig() {
        AppDefaults.saveConfig(config, to: defaults)
    }

    func applyLaunchAtLoginPreference() {
        launchAtLoginCoordinator.apply(config: &config)
    }

    func reconcileLaunchAtLoginFromService() {
        launchAtLoginCoordinator.reconcile(config: &config)
    }

    // MARK: - Volume

    /// Asks the speakers for `level`. The controls show it at once; it is sent as soon as the
    /// speakers have answered the previous request, and levels asked for meanwhile replace it.
    func setLevel(_ level: Double) {
        // No level is known unless connected, so read it first instead of sending one derived from it.
        guard connection == .connected else {
            refresh()
            return
        }
        // Compared before clamping, so a step up at the limit is still refused.
        if blocksVolumeIncrease && level > self.level { return }

        targetLevel = min(config.effectiveMax, max(0, level))
        guard !isWriting else { return }
        isWriting = true
        enqueue { await self.writeTargetLevel() }
    }

    /// Relative volume change from a delta (e.g. hotkey step).
    func adjustVolume(by delta: Double) {
        setLevel(level + delta)
    }

    func toggleMute() async {
        guard connection == .connected else {
            refresh()
            return
        }
        await enqueue { await self.writeMuteToggle() }.value
    }

    private func writeMuteToggle() async {
        // An operation queued before this one may have failed.
        guard connection == .connected else { return }
        do {
            outputs = try await speakers.setMuted(!isMuted)
        } catch {
            fail(error)
        }
    }

    /// Sends the target level until the speakers have the latest one.
    private func writeTargetLevel() async {
        defer { isWriting = false }
        var written: Double?
        while let target = targetLevel, target != written {
            do {
                outputs = try await speakers.setLevel(target)
                written = target
            } catch {
                fail(error)
                return
            }
        }
        targetLevel = nil
    }

    // MARK: - Connection

    /// Reads the speakers' outputs, connecting first when needed. Does nothing while a read is
    /// already queued or a level is being written, since either brings fresh outputs.
    func refresh() {
        guard !isRefreshing, !isWriting else { return }
        isRefreshing = true
        // The first connect may have to search; a later one retries or re-reads without blocking the controls.
        if connection == .disconnected { connection = .searching }
        enqueue {
            defer { self.isRefreshing = false }
            await self.connect(rescan: false)
        }
    }

    /// Popover open: refresh the interface list and the speakers' outputs.
    func preparePopover() {
        loadInterfaces()
        refresh()
    }

    func selectInterface(_ name: String) async {
        guard !isSearching else { return }
        targetLevel = nil
        config.networkInterface = name
        saveConfig()
        connection = .searching
        await enqueue { await self.connect(rescan: true) }.value
    }

    private func connect(rescan: Bool) async {
        if rescan { connection = .searching }
        do {
            outputs = try await speakers.connect(interface: config.networkInterface, rescan: rescan)
            connection = .connected
        } catch {
            fail(error)
        }
    }

    /// Nothing is known about the speakers any more, so nothing is shown or sent until a read succeeds.
    private func fail(_ error: SpeakerError) {
        connection = .failed(error)
        outputs = []
        targetLevel = nil
    }

    // MARK: - Speaker operations

    /// Runs `operation` after every speaker operation queued before it, so results are applied in
    /// the order the requests were made.
    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = lastOperation
        let task = Task {
            await previous?.value
            await operation()
        }
        lastOperation = task
        return task
    }

    /// Waits until no speaker operation is queued or running.
    func settle() async {
        while let task = lastOperation {
            await task.value
            if lastOperation == task { lastOperation = nil }
        }
    }

    // MARK: - Network and sleep

    func loadInterfaces() {
        interfaces = listInterfaces()
    }

    private func setupNetworkMonitor() {
        if networkMonitor == nil {
            networkMonitor = SystemNetworkMonitorService()
        }
        networkMonitor?.onPathChange = { [weak self] isSatisfied in
            self?.handleNetworkPathChange(isSatisfied: isSatisfied)
        }
        networkMonitor?.start()
    }

    private func observeSleep() {
        // Free the speakers' connection slots while asleep; requests reconnect after wake.
        // No quit handler is needed: the kernel closes BSD sockets when the process exits.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.disconnectSpeakers() }
        }
    }

    /// Not queued behind other operations: closing is safe at any time and returns nothing to apply.
    private func disconnectSpeakers() {
        Task { await speakers.disconnect() }
    }

    private func handleNetworkPathChange(isSatisfied: Bool) {
        // Connections do not survive a network change; the next request reconnects.
        disconnectSpeakers()

        guard isSatisfied else { return }

        // Network restored: debounce to absorb rapid back-to-back firings
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task {
            try? await Task.sleep(for: networkRecoveryDelay)
            guard !Task.isCancelled else { return }
            loadInterfaces()
            // Reconnect only when not connected, to avoid interrupting normal operation
            if connection != .connected && !interfaces.isEmpty {
                refresh()
            }
        }
    }
}
