import Foundation
import Observation

enum StorePhase: Equatable {
    case idle
    case loading(LoadReason)
    case committingVolume(level: Double)

    enum LoadReason: Equatable {
        case refresh
        case interfaceSelection(name: String)
        case mutation
    }

    var isBusy: Bool { self != .idle }
    var isStatusLoading: Bool {
        if case .loading = self { return true }
        return false
    }
    var isVolumeCommitting: Bool {
        if case .committingVolume = self { return true }
        return false
    }
}

private enum PhaseEvent {
    case loadBegan(StorePhase.LoadReason)
    case loadCompleted(Result<KhvolJSONStatus, any Error>)
    case commitBegan(level: Double)
    case commitCompleted(targetLevel: Double, Result<KhvolJSONStatus, any Error>)
}

// MARK: - SpeakerStoreTiming

/// Injectable timing constants — set to `.testing` in unit tests to eliminate real sleeps.
struct SpeakerStoreTiming {
    /// Minimum interval between consecutive volume commits to the device.
    var volumeThrottleInterval: Duration = .milliseconds(200)
    /// Trailing-debounce delay before the final volume commit fires.
    var volumeTrailingDelay: Duration = .milliseconds(120)
    /// Debounce applied after a network path change before attempting recovery.
    var networkRecoveryDelay: Duration = .milliseconds(500)
    /// How long a cached interface list is considered fresh before reloading.
    var interfacesReloadInterval: TimeInterval = 60
}

extension SpeakerStoreTiming {
    /// All delays zeroed out so tests run without real sleeps.
    static let testing = SpeakerStoreTiming(
        volumeThrottleInterval: .zero,
        volumeTrailingDelay: .zero,
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
    var isBusy: Bool { phase.isBusy }
    /// True while status refresh, scan, or other non-volume mutations are in flight.
    var isStatusLoading: Bool { phase.isStatusLoading }
    /// Terminal connection state (ready/warning/disconnected). Use `connection` for display.
    private var connectionState: ConnectionState = .disconnected
    /// Derives `.scanning` from `phase`, so the stored value never needs to be `.scanning`.
    var connection: ConnectionState { phase.isStatusLoading ? .scanning : connectionState }
    /// Forwarded from `launchAtLoginCoordinator.errorMessage`.
    var launchAtLoginMessage: String? { launchAtLoginCoordinator.errorMessage }
    /// Uncommitted target level shared by hotkeys, popover slider, and HUD preview.
    var pendingVolumeLevel: Double?

    /// Manages LaunchAtLogin preference and owns its error-message state.
    /// Injected in tests; production init creates a real `LaunchAtLoginCoordinator`.
    let launchAtLoginCoordinator: any LaunchAtLoginManaging

    private var refreshTask: Task<Void, Never>?
    private var volumeTrailingTask: Task<Void, Never>?
    /// Retained HotkeyService instance (production: HotkeyManager; tests: mock).
    private var hotkeyService: (any HotkeyService)?
    private var hasStartedUp = false
    private var lastInterfacesLoad: Date?
    var isVolumeCommitting: Bool { phase.isVolumeCommitting }
    private var lastVolumeCommitStart: ContinuousClock.Instant? = nil
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
        switch await fetchStatus(attemptRecovery: true) {
        case .success(let json):
            apply(json: json)
            connectionState = json.balanced ? .ready : .warning
            status.lastError = nil
        case .failure(let err):
            connectionState = .disconnected
            status.lastError = err.localizedDescription
            if err is KhvolError { status.devices = [] }
        }
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
    func preparePopover() async {
        await loadInterfacesIfNeeded()
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
            let count = try await makeClient().scan()
            guard count > 0 else { return nil }
            return try await makeClient().jsonStatus()
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

    func loadInterfacesIfNeeded() async {
        if !interfaces.isEmpty,
           let last = lastInterfacesLoad,
           now().timeIntervalSince(last) < timing.interfacesReloadInterval {
            return
        }
        await loadInterfaces(force: true)
    }

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

    @MainActor
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
                _ = try await makeClient().scan()
                return .success(try await makeClient().jsonStatus())
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

        pendingVolumeLevel = requested
        status.lastError = nil

        if isBusy { return }
        scheduleThrottledCommit()
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
        volumeTrailingTask?.cancel()
        volumeTrailingTask = nil
        pendingVolumeLevel = nil
    }

    // MARK: - Volume commit throttle

    private func scheduleThrottledCommit() {
        volumeTrailingTask?.cancel()

        let throttleElapsed = lastVolumeCommitStart.map { ContinuousClock.now - $0 } ?? timing.volumeThrottleInterval
        if !isVolumeCommitting && throttleElapsed >= timing.volumeThrottleInterval {
            lastVolumeCommitStart = .now
            Task { await commitPendingVolume() }
            scheduleTrailingTask()
            return
        }
        scheduleTrailingTask()
    }

    private func scheduleTrailingTask() {
        volumeTrailingTask?.cancel()
        volumeTrailingTask = Task {
            try? await Task.sleep(for: timing.volumeTrailingDelay)
            guard !Task.isCancelled else { return }
            await trailingCommitFire()
        }
    }

    private func trailingCommitFire() async {
        guard pendingVolumeLevel != nil, case .idle = phase else { return }
        lastVolumeCommitStart = .now
        await commitPendingVolume()
    }

    func commitPendingVolume() async {
        guard let levelToCommit = pendingVolumeLevel else { return }
        await executeVolumeLevelMutation(level: levelToCommit) {
            try await $0.setLevel(levelToCommit)
        }
    }

    @discardableResult
    private func executeVolumeLevelMutation(
        level: Double,
        _ body: (any KhvolClientProtocol) async throws -> KhvolJSONStatus
    ) async -> Bool {
        guard case .idle = phase else { return false }
        reduce(.commitBegan(level: level))
        do {
            let json = try await body(makeClient())
            reduce(.commitCompleted(targetLevel: level, .success(json)))
            return true
        } catch {
            reduce(.commitCompleted(targetLevel: level, .failure(error)))
            return false
        }
    }

    private func flushVolumeCommitAfterBusyIfNeeded() {
        guard pendingVolumeLevel != nil else { return }
        scheduleThrottledCommit()
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
            flushVolumeCommitAfterBusyIfNeeded()

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
            flushVolumeCommitAfterBusyIfNeeded()

        case (.idle, .commitBegan(let level)):
            phase = .committingVolume(level: level)

        case (.committingVolume(let inFlight), .commitCompleted(let target, .success(let json)))
             where inFlight == target:
            apply(json: json)
            connectionState = json.balanced ? .ready : .warning
            status.lastError = nil
            phase = .idle
            if pendingVolumeLevel != target {
                scheduleThrottledCommit()
            } else {
                pendingVolumeLevel = nil
            }

        case (.committingVolume, .commitCompleted(_, .failure(let err))):
            applyError(err)
            phase = .idle
            if pendingVolumeLevel != nil {
                scheduleTrailingTask()
            }

        default:
            assertionFailure("unexpected transition: \(phase) + \(event)")
        }
    }

    private func applyError(_ err: any Error) {
        lastInterfacesLoad = nil
        status.lastError = err.localizedDescription
        connectionState = .disconnected
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

    func apply(json: KhvolJSONStatus) {
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
