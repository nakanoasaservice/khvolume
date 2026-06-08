import Foundation
import Observation

enum StorePhase: Equatable {
    case idle
    case loading(LoadReason)

    enum LoadReason: Equatable {
        case refresh
        case interfaceSelection(name: String)
        case mutation
    }

    var isStatusLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private enum PhaseEvent {
    case loadBegan(StorePhase.LoadReason)
    case loadCompleted(Result<KhvolJSONStatus, any Error>)
    case silentRefreshCompleted(Result<KhvolJSONStatus, any Error>)
}

private enum VolumeState {
    case idle
    case pending(level: Double, lastCommitStart: ContinuousClock.Instant?)
    case committing(level: Double, commitStart: ContinuousClock.Instant)

    var pendingLevel: Double? {
        switch self {
        case .idle: nil
        case .pending(let level, _): level
        case .committing(let level, _): level
        }
    }
}

private enum VolumeEvent {
    case previewSet(Double)
    case cancelled
    case throttleExpired
    case commitSucceeded(KhvolJSONStatus)
    case commitFailed(any Error)
}

// MARK: - SpeakerStoreTiming

/// Injectable timing constants — set to `.testing` in unit tests to eliminate real sleeps.
struct SpeakerStoreTiming {
    /// Minimum interval between consecutive volume commits to the device.
    var volumeThrottleInterval: Duration = .milliseconds(200)
    /// Debounce applied after a network path change before attempting recovery.
    var networkRecoveryDelay: Duration = .milliseconds(500)
    /// How long a cached interface list is considered fresh before reloading.
    var interfacesReloadInterval: TimeInterval = 60
}

extension SpeakerStoreTiming {
    /// All delays zeroed out so tests run without real sleeps.
    static let testing = SpeakerStoreTiming(
        volumeThrottleInterval: .zero,
        networkRecoveryDelay: .zero,
        interfacesReloadInterval: 0
    )
}

// MARK: - SpeakerStore

@Observable
@MainActor
final class SpeakerStore {
    var config: AppConfig
    var status = SpeakerStatus()
    var interfaces: [NetworkInterfaceInfo] = []
    var phase: StorePhase = .idle
    /// True while status refresh, scan, or other non-volume mutations are in flight.
    var isStatusLoading: Bool { phase.isStatusLoading }
    /// Terminal connection state (ready/warning/disconnected). Use `connection` for display.
    private var connectionState: ConnectionState = .disconnected
    /// Derives `.scanning` from `phase`, so the stored value never needs to be `.scanning`.
    var connection: ConnectionState { phase.isStatusLoading ? .scanning : connectionState }
    /// Forwarded from `launchAtLoginCoordinator.errorMessage`.
    var launchAtLoginMessage: String? { launchAtLoginCoordinator.errorMessage }
    /// Uncommitted target level shared by hotkeys, popover slider, and HUD preview.
    var pendingVolumeLevel: Double? {
        get { volumeState.pendingLevel }
        set {
            if let v = newValue {
                volumeState = .pending(level: v, lastCommitStart: nil)
            } else {
                volumeState = .idle
            }
        }
    }

    /// Manages LaunchAtLogin preference and owns its error-message state.
    /// Injected in tests; production init creates a real `LaunchAtLoginCoordinator`.
    let launchAtLoginCoordinator: any LaunchAtLoginManaging

    private var refreshTask: Task<Void, Never>?
    private var volumeCommitTask: Task<Void, Never>?
    /// Retained HotkeyService instance (production: HotkeyManager; tests: mock).
    private var hotkeyService: (any HotkeyService)?
    private var hasStartedUp = false
    private var lastInterfacesLoad: Date?
    private var volumeState: VolumeState = .idle
    private var networkMonitor: (any NetworkMonitorService)?
    private var networkRecoveryTask: Task<Void, Never>?

    /// Injected in tests; nil means production path creates KhvolClient directly.
    private let clientFactory: (() -> any KhvolClientProtocol)?
    /// Timing constants — replaced with `.testing` in unit tests to eliminate real sleeps.
    private let timing: SpeakerStoreTiming
    /// Returns whether a speaker-config cache file exists on disk.
    /// Injected in tests to decouple `shouldRescan` from the filesystem.
    private let hasSpeakerCache: () -> Bool
    /// Returns the current date/time.
    /// Injected in tests to make interface-cache TTL logic deterministic.
    private let now: () -> Date

    init() {
        config = AppPaths.loadConfig()
        clientFactory = nil
        launchAtLoginCoordinator = LaunchAtLoginCoordinator()
        hasSpeakerCache = { AppPaths.hasSpeakerCache }
        now = { Date() }
        timing = SpeakerStoreTiming()
        KhVolumeBootstrap.store = self
        Task { await startupIfNeeded() }
    }

    /// Testing initializer — all infrastructure dependencies are injectable.
    ///
    /// - Parameters:
    ///   - suppressStartup: When `true` (the default), sets `hasStartedUp = true` so that
    ///     `startupIfNeeded()` is a no-op even if called manually.
    ///     Pass `false` and call `startupIfNeeded()` explicitly to test the startup path.
    init(
        config: AppConfig,
        clientFactory: @escaping () -> any KhvolClientProtocol,
        networkMonitor: (any NetworkMonitorService)? = nil,
        hotkeyService: (any HotkeyService)? = nil,
        launchAtLoginCoordinator: (any LaunchAtLoginManaging)? = nil,
        hasSpeakerCache: @escaping () -> Bool = { AppPaths.hasSpeakerCache },
        now: @escaping () -> Date = { Date() },
        timing: SpeakerStoreTiming = SpeakerStoreTiming(),
        suppressStartup: Bool = true
    ) {
        self.config = config
        self.clientFactory = clientFactory
        self.networkMonitor = networkMonitor
        self.hotkeyService = hotkeyService
        self.launchAtLoginCoordinator = launchAtLoginCoordinator ?? LaunchAtLoginCoordinator()
        self.hasSpeakerCache = hasSpeakerCache
        self.now = now
        self.timing = timing
        if suppressStartup { self.hasStartedUp = true }
    }

    // MARK: - Startup

    /// Called at launch so volume and hotkeys work without opening the menu bar popover.
    func startupIfNeeded() async {
        guard !hasStartedUp else { return }
        hasStartedUp = true

        if hotkeyService == nil {
            let manager = HotkeyManager(store: self)
            hotkeyService = manager
        }
        hotkeyService?.register()

        launchAtLoginCoordinator.reconcile(config: &config)
        setupNetworkMonitor()
        await loadInterfaces()
        scheduleRefresh()
    }

    // MARK: - Computed properties

    var interfaceName: String? {
        config.networkInterface
    }

    /// Current level for all volume UI, including uncommitted hotkey preview.
    var previewAverageLevel: Double {
        pendingVolumeLevel ?? status.averageLevel
    }

    private func clampVolume(_ level: Double) -> Double {
        min(config.effectiveMax, max(0, level))
    }

    var blocksVolumeIncrease: Bool {
        status.levelMismatch && !config.allowForceOnMismatch
    }

    // MARK: - Client

    private func makeClient() -> any KhvolClientProtocol {
        if let factory = clientFactory {
            return factory()
        }
        return KhvolClient(configDir: AppPaths.appSupportURL, interface: interfaceName)
    }

    // MARK: - Config persistence

    func saveConfig() {
        AppPaths.saveConfig(config)
    }

    func applyLaunchAtLoginPreference() {
        launchAtLoginCoordinator.apply(config: &config)
    }

    func reconcileLaunchAtLoginFromService() {
        launchAtLoginCoordinator.reconcile(config: &config)
    }

    // MARK: - Status refresh

    func refresh() async {
        guard case .idle = phase else { return }
        await withLoadPhase(.refresh) {
            await fetchStatus(attemptRecovery: true)
        }
    }

    /// Status-only refresh that never sets a loading phase — safe to call during active UI interaction.
    private func refreshSilently() async {
        guard case .idle = phase else { return }
        guard case .idle = volumeState else { return }
        reduce(.silentRefreshCompleted(await fetchStatus(attemptRecovery: true)))
    }

    /// Acquire the load phase, yield for UI, run `fetch`, then release. Caller must guard `.idle` first.
    private func withLoadPhase(
        _ reason: StorePhase.LoadReason,
        _ fetch: () async -> Result<KhvolJSONStatus, any Error>
    ) async {
        reduce(.loadBegan(reason))
        await Task.yield()
        let result = await fetch()
        reduce(.loadCompleted(result))
    }

    /// Popover open: refresh interface list and status without blocking controls or rescanning.
    /// Popover open: refresh interface list and status without blocking controls or rescanning.
    func preparePopover() async {
        await loadInterfaces()
        await refreshSilently()
    }

    private func fetchStatus(attemptRecovery: Bool) async -> Result<KhvolJSONStatus, any Error> {
        do {
            return .success(try await makeClient().jsonStatus())
        } catch let err as KhvolError {
            if attemptRecovery, let recovered = await recoverAfterDeviceError(err) {
                return .success(recovered)
            }
            return .failure(err)
        } catch {
            return .failure(error)
        }
    }

    /// Rescan only when the speaker cache is missing or a rescan keyword is in the error message.
    private func recoverAfterDeviceError(_ err: KhvolError) async -> KhvolJSONStatus? {
        guard case .deviceError(let message) = err, shouldRescan(after: message) else { return nil }
        await loadInterfaces(force: true)
        do {
            let client = makeClient()
            let count = try await client.scan()
            guard count > 0 else { return nil }
            return try await client.jsonStatus()
        } catch {
            return nil
        }
    }

    func shouldRescan(after message: String) -> Bool {
        if !hasSpeakerCache() { return true }
        let lower = message.lowercased()
        return lower.contains("run scan") || lower.contains("no speakers configured")
    }

    // MARK: - Interface loading

    func loadInterfaces(force: Bool = false) async {
        if !force,
           !interfaces.isEmpty,
           let last = lastInterfacesLoad,
           now().timeIntervalSince(last) < timing.interfacesReloadInterval {
            return
        }
        do {
            interfaces = try await makeClient().interfaces()
            lastInterfacesLoad = now()
        } catch {
            interfaces = []
        }
    }

    // MARK: - Network monitoring

    private func setupNetworkMonitor() {
        if networkMonitor == nil {
            networkMonitor = SystemNetworkMonitorService()
        }
        networkMonitor?.onPathChange = { [weak self] isSatisfied in
            self?.handleNetworkPathChange(isSatisfied: isSatisfied)
        }
        networkMonitor?.start()
    }

    private func handleNetworkPathChange(isSatisfied: Bool) {
        // Invalidate the interface cache on any network change
        lastInterfacesLoad = nil

        guard isSatisfied else { return }

        // Network restored: debounce to absorb rapid back-to-back firings
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task {
            try? await Task.sleep(for: timing.networkRecoveryDelay)
            guard !Task.isCancelled else { return }
            await loadInterfaces()
            // Auto-refresh only when disconnected to avoid interrupting normal operation
            if connectionState == .disconnected && !interfaces.isEmpty {
                await refreshSilently()
            }
        }
    }

    // MARK: - Interface selection

    func selectInterface(_ name: String) async {
        guard case .idle = phase else { return }
        cancelPendingVolume()
        config.networkInterface = name
        saveConfig()
        await withLoadPhase(.interfaceSelection(name: name)) {
            do {
                let client = makeClient()
                _ = try await client.scan()
                return .success(try await client.jsonStatus())
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - Volume preview / adjust

    /// Updates the shared preview level and debounces commit to the device.
    func setVolumePreview(_ level: Double) {
        guard !isStatusLoading else { return }

        let requested = clampVolume(level)
        if blocksVolumeIncrease && requested > previewAverageLevel {
            status.lastError = "Left and right levels do not match"
            return
        }

        status.lastError = nil
        reduceVolume(.previewSet(requested))
    }

    /// Relative volume change from a delta (e.g. hotkey step).
    func adjustVolume(by delta: Double) {
        guard !isStatusLoading else { return }
        guard volumeChangeAllowed(delta: delta) else { return }

        let base = pendingVolumeLevel ?? status.averageLevel
        setVolumePreview(base + delta)
    }

    private func volumeChangeAllowed(delta: Double) -> Bool {
        if delta > 0 && blocksVolumeIncrease {
            status.lastError = "Left and right levels do not match"
            return false
        }
        return true
    }

    func toggleMute() async {
        cancelPendingVolume()
        let targetMuted = !status.isMuted
        await runMutation { try await $0.setMuted(targetMuted) }
    }

    func cancelPendingVolume() {
        reduceVolume(.cancelled)
    }

    /// Awaits the current volume commit task to completion.
    /// Use after `setVolumePreview(_:)` to synchronise with the commit task.
    func awaitVolumeCommit() async {
        await volumeCommitTask?.value
    }

    // MARK: - Volume commit

    private func scheduleVolumeCommit() {
        volumeCommitTask = Task {
            guard !Task.isCancelled else { return }
            guard case .pending(_, let lastCommitStart) = volumeState else { return }
            if let last = lastCommitStart {
                let remaining = timing.volumeThrottleInterval - (ContinuousClock.now - last)
                if remaining > .zero {
                    try? await Task.sleep(for: remaining)
                    guard !Task.isCancelled else { return }
                }
            }
            guard case .pending(let levelToCommit, _) = volumeState else { return }
            reduceVolume(.throttleExpired)
            let client = makeClient()
            do {
                let json = try await client.setLevel(levelToCommit)
                reduceVolume(.commitSucceeded(json))
            } catch {
                reduceVolume(.commitFailed(error))
            }
        }
    }

    

    // MARK: - FSM reducer

    private func reduce(_ event: PhaseEvent) {
        switch (phase, event) {

        case (.idle, .loadBegan(let reason)):
            refreshTask?.cancel()
            status.lastError = nil
            phase = .loading(reason)

        case (.loading, .loadCompleted(.success(let json))):
            apply(json: json)
            connectionState = json.balanced ? .ready : .warning
            status.lastError = nil
            phase = .idle

        case (.loading(let reason), .loadCompleted(.failure(let err))):
            connectionState = .disconnected
            status.lastError = err.localizedDescription
            switch reason {
            case .refresh, .interfaceSelection:
                if err is KhvolError { status.devices = [] }
            case .mutation:
                lastInterfacesLoad = nil
            }
            phase = .idle

        case (_, .silentRefreshCompleted(.success(let json))):
            apply(json: json)
            connectionState = json.balanced ? .ready : .warning
            status.lastError = nil

        case (_, .silentRefreshCompleted(.failure(let err))):
            connectionState = .disconnected
            status.lastError = err.localizedDescription
            if err is KhvolError { status.devices = [] }

        default:
            assertionFailure("unexpected transition: \(phase) + \(event)")
        }
    }

    private func reduceVolume(_ event: VolumeEvent) {
        switch (volumeState, event) {

        case (_, .previewSet(let level)):
            let lastCommitStart: ContinuousClock.Instant?
            switch volumeState {
            case .idle:
                lastCommitStart = nil
            case .pending(_, let ts):
                lastCommitStart = ts
            case .committing(_, let start):
                lastCommitStart = start
            }
            volumeCommitTask?.cancel()
            volumeState = .pending(level: level, lastCommitStart: lastCommitStart)
            scheduleVolumeCommit()

        case (_, .cancelled):
            volumeCommitTask?.cancel()
            volumeCommitTask = nil
            volumeState = .idle

        case (.pending(let level, _), .throttleExpired):
            volumeState = .committing(level: level, commitStart: ContinuousClock.now)

        case (_, .commitSucceeded(let json)):
            apply(json: json)
            connectionState = json.balanced ? .ready : .warning
            status.lastError = nil
            if case .committing = volumeState { volumeState = .idle }

        case (.committing(let level, _), .commitFailed(let err)):
            connectionState = .disconnected
            status.lastError = err.localizedDescription
            lastInterfacesLoad = nil
            if err is KhvolError { status.devices = [] }
            volumeState = .pending(level: level, lastCommitStart: nil)

        case (_, .commitFailed(let err)):
            connectionState = .disconnected
            status.lastError = err.localizedDescription
            lastInterfacesLoad = nil
            if err is KhvolError { status.devices = [] }

        default:
            assertionFailure("unexpected volume transition: \(volumeState) + \(event)")
        }
    }

    private func runMutation(_ body: (any KhvolClientProtocol) async throws -> KhvolJSONStatus) async {
        guard case .idle = phase else { return }
        await withLoadPhase(.mutation) {
            do {
                return .success(try await body(makeClient()))
            } catch {
                return .failure(error)
            }
        }
    }

    private func apply(json: KhvolJSONStatus) {
        status.isMuted = json.muted
        status.levelMismatch = !json.balanced
        status.devices = json.devices.map { key, val in
            DeviceLevel(
                id: key,
                name: key,
                level: val.level ?? 0,
                muted: val.mute ?? false
            )
        }.sorted { $0.name < $1.name }
        status.averageLevel = json.levels.isEmpty ? 0 : json.levels.reduce(0, +) / Double(json.levels.count)
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }
}
