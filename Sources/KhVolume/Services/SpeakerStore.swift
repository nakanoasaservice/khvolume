import AppKit
import Observation

/// The app's state: settings, what the speakers report, and what the user asked of them.
@Observable
@MainActor
final class SpeakerStore {
    var config: AppConfig
    var interfaces: [NetworkInterface] = []
    /// What the speakers last reported; empty while nothing is known.
    /// Not `private(set)` so tests can start from a known state, like `connection`.
    var outputs: [SpeakerOutput] = []
    var connection: ConnectionState = .disconnected
    /// The level the user asked for, until the speakers have confirmed it.
    private(set) var targetLevel: Double?

    private let speakers: any SpeakerGroup
    private let listInterfaces: () -> [NetworkInterface]
    private let defaults: UserDefaults
    private let networkMonitor: any NetworkPathMonitor
    /// Debounce applied after a network path change before attempting recovery.
    private let networkRecoveryDelay: Duration
    private var networkRecoveryTask: Task<Void, Never>?

    /// The speaker operation queued last; each one waits for the one before it.
    private var lastOperation: Task<Void, Never>?
    private var isWriting = false
    private var isRefreshing = false

    /// The default arguments are the real app's; tests pass their own (see `makeForTesting`).
    /// `config` is loaded from `defaults` when it is not given.
    init(
        config: AppConfig? = nil,
        speakers: any SpeakerGroup = SSCSpeakerGroup(),
        listInterfaces: @escaping () -> [NetworkInterface] = NetworkInterfaceLister.list,
        defaults: UserDefaults = .standard,
        networkMonitor: (any NetworkPathMonitor)? = nil,
        networkRecoveryDelay: Duration = .milliseconds(500)
    ) {
        self.config = config ?? AppDefaults.loadConfig(from: defaults)
        self.speakers = speakers
        self.listInterfaces = listInterfaces
        self.defaults = defaults
        self.networkMonitor = networkMonitor ?? SystemNetworkPathMonitor()
        self.networkRecoveryDelay = networkRecoveryDelay
    }

    // MARK: - Startup

    /// Starts watching the network and sleep, and reads the speakers. The app calls this once at
    /// launch, not from a view, so that volume and hotkeys work before the popover is opened.
    func start() {
        watchNetwork()
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

    var blocksLevelIncrease: Bool {
        !isBalanced && !config.allowsIncreaseWhileUnbalanced
    }

    var errorMessage: String? {
        if case .failed(let error) = connection { error.errorDescription } else { nil }
    }

    // MARK: - Config persistence

    func saveConfig() {
        AppDefaults.saveConfig(config, to: defaults)
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
        if blocksLevelIncrease && level > self.level { return }

        targetLevel = level.clamped(to: 0...config.maxLevel)
        guard !isWriting else { return }
        isWriting = true
        enqueue { await self.writeTargetLevel() }
    }

    /// Changes the level by `delta` (a hotkey step).
    func adjustLevel(by delta: Double) {
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
        config.networkInterface = name
        saveConfig()
        await search()
    }

    /// Reload button: lists the interfaces again and searches the selected one for speakers.
    func reload() async {
        guard !isSearching else { return }
        loadInterfaces()
        await search()
    }

    private func search() async {
        targetLevel = nil
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

    private func watchNetwork() {
        networkMonitor.onPathChange = { [weak self] isSatisfied in
            self?.handleNetworkPathChange(isSatisfied: isSatisfied)
        }
        networkMonitor.start()
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
