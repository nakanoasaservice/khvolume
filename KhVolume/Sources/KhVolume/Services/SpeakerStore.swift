import Foundation
import Network
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
    var launchAtLoginMessage: String?
    /// Uncommitted target level shared by hotkeys, popover slider, and HUD preview.
    var pendingVolumeLevel: Double?

    private var refreshTask: Task<Void, Never>?
    private var volumeTrailingTask: Task<Void, Never>?
    private var hotkeyManager: HotkeyManager?
    private var hasStartedUp = false
    private var lastInterfacesLoad: Date?
    var isVolumeCommitting: Bool { phase.isVolumeCommitting }
    private let volumeThrottleInterval: Duration = .milliseconds(200)
    private let volumeTrailingDelay: Duration = .milliseconds(120)
    private var lastVolumeCommitStart: ContinuousClock.Instant? = nil
    private let interfacesReloadInterval: TimeInterval = 60
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.khvolume.pathmonitor", qos: .utility)
    private var networkRecoveryTask: Task<Void, Never>?

    /// Injected in tests; nil means production path creates KhvolClient directly.
    private let clientFactory: (() -> any KhvolClientProtocol)?

    init() {
        config = AppPaths.loadConfig()
        clientFactory = nil
        KhVolumeBootstrap.store = self
        Task { await startupIfNeeded() }
    }

    /// Test-only initializer — skips subprocess setup, hotkeys, and NWPathMonitor.
    init(config: AppConfig, clientFactory: @escaping () -> any KhvolClientProtocol) {
        self.config = config
        self.clientFactory = clientFactory
        self.hasStartedUp = true   // prevents startupIfNeeded from firing
    }

    /// Called at launch so volume and hotkeys work without opening the menu bar popover.
    func startupIfNeeded() async {
        guard !hasStartedUp else { return }
        hasStartedUp = true

        if hotkeyManager == nil {
            let manager = HotkeyManager(store: self)
            manager.register()
            hotkeyManager = manager
        }

        reconcileLaunchAtLoginFromService()
        startNetworkMonitor()
        await loadInterfaces()
        scheduleRefresh()
    }

    var interfaceName: String? {
        config.networkInterface
    }

    /// Current level for all volume UI, including uncommitted hotkey preview.
    var previewAverageLevel: Double {
        pendingVolumeLevel ?? status.averageLevel
    }

    /// Formatted level label shared by HUD and popover.
    func volumeLevelText(for level: Double) -> String {
        if status.isMuted { return "—" }
        return "\(Int(level.rounded()))"
    }

    var volumeLevelText: String {
        volumeLevelText(for: previewAverageLevel)
    }

    /// Normalized slider position (0...1) shared by HUD and popover.
    var volumeFraction: Double {
        guard config.effectiveMax > 0, !status.isMuted else { return 0 }
        return min(1, max(0, previewAverageLevel / config.effectiveMax))
    }

    var isVolumeSliderDisabled: Bool {
        status.isMuted || isStatusLoading
    }

    private func clampVolume(_ level: Double) -> Double {
        min(config.effectiveMax, max(0, level))
    }

    var blocksVolumeIncrease: Bool {
        status.levelMismatch && !config.allowForceOnMismatch
    }

    private func makeClient() -> any KhvolClientProtocol {
        if let factory = clientFactory {
            return factory()
        }
        return KhvolClient(configDir: AppPaths.appSupportURL, interface: interfaceName)
    }

    func saveConfig() {
        AppPaths.saveConfig(config)
        applyLaunchAtLoginPreference()
    }

    func applyLaunchAtLoginPreference() {
        let result = LaunchAtLogin.setEnabled(config.launchAtLogin)
        switch result {
        case .success:
            launchAtLoginMessage = nil
            config.launchAtLogin = LaunchAtLogin.serviceIsEnabled
        case .unavailable(let message):
            launchAtLoginMessage = message
            config.launchAtLogin = false
            AppPaths.saveConfig(config)
        }
    }

    func reconcileLaunchAtLoginFromService() {
        let enabled = LaunchAtLogin.serviceIsEnabled
        if config.launchAtLogin != enabled {
            config.launchAtLogin = enabled
            AppPaths.saveConfig(config)
        }
    }


    func refresh() async {
        guard case .idle = phase else { return }
        await withLoadPhase(.refresh) {
            await fetchStatus(attemptRecovery: true)
        }
    }

    /// Status-only refresh that never sets a loading phase — safe to call during active UI interaction.
    /// Status-only refresh that never sets a loading phase — safe to call during active UI interaction.
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

    /// Rescan only when the speaker cache is missing (not on every transient json failure).
    /// Rescan only when the speaker cache is missing (not on every transient json failure).
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
        if !AppPaths.hasSpeakerCache { return true }
        let lower = message.lowercased()
        return lower.contains("run scan") || lower.contains("no speakers configured")
    }

    func loadInterfacesIfNeeded() async {
        if !interfaces.isEmpty,
           let last = lastInterfacesLoad,
           Date().timeIntervalSince(last) < interfacesReloadInterval {
            return
        }
        await loadInterfaces(force: true)
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handleNetworkPathChange(path)
            }
        }
        monitor.start(queue: pathMonitorQueue)
        pathMonitor = monitor
    }

    @MainActor
    private func handleNetworkPathChange(_ path: NWPath) {
        // Invalidate the interface cache on any network change
        lastInterfacesLoad = nil

        guard path.status == .satisfied else { return }

        // Network restored: debounce 0.5s to absorb rapid back-to-back firings
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await loadInterfaces()
            // Auto-refresh only when disconnected to avoid interrupting normal operation
            if connectionState == .disconnected && !interfaces.isEmpty {
                await refreshSilently()
            }
        }
    }

    func loadInterfaces(force: Bool = false) async {
        if !force,
           !interfaces.isEmpty,
           let last = lastInterfacesLoad,
           Date().timeIntervalSince(last) < interfacesReloadInterval {
            return
        }
        do {
            interfaces = try await makeClient().interfaces()
            lastInterfacesLoad = Date()
        } catch {
            interfaces = []
        }
    }

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

    /// Updates the shared preview level and debounces commit to the device.
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

    private func scheduleThrottledCommit() {
        volumeTrailingTask?.cancel()

        let throttleElapsed = lastVolumeCommitStart.map { ContinuousClock.now - $0 } ?? volumeThrottleInterval
        if !isVolumeCommitting && throttleElapsed >= volumeThrottleInterval {
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
            try? await Task.sleep(for: volumeTrailingDelay)
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

    // MARK: – FSM reducer

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
