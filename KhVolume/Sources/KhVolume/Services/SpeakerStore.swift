import Foundation
import Network
import Observation

@Observable
@MainActor
final class SpeakerStore {
    var config: AppConfig
    var status = SpeakerStatus()
    var interfaces: [NetworkInterfaceInfo] = []
    var isBusy = false
    /// True while status refresh, scan, or other non-volume mutations are in flight.
    private(set) var isStatusLoading = false
    var launchAtLoginMessage: String?
    /// Uncommitted target level shared by hotkeys, popover slider, and HUD preview.
    var pendingVolumeLevel: Double?

    private var refreshTask: Task<Void, Never>?
    private var volumeTrailingTask: Task<Void, Never>?
    private var hotkeyManager: HotkeyManager?
    private var hasStartedUp = false
    private var lastInterfacesLoad: Date?
    /// When volume input arrives during commit, schedule again after the current operation finishes.
    private var volumeCommitPendingAfterBusy = false
    private(set) var isVolumeCommitting = false
    private let volumeThrottleInterval: Duration = .milliseconds(200)
    private let volumeTrailingDelay: Duration = .milliseconds(120)
    private var lastVolumeCommitStart: ContinuousClock.Instant? = nil
    private let interfacesReloadInterval: TimeInterval = 60
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.khvolume.pathmonitor", qos: .utility)
    private var networkRecoveryTask: Task<Void, Never>?

    init() {
        config = AppPaths.loadConfig()
        KhVolumeBootstrap.store = self
        Task { await startupIfNeeded() }
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

    private func makeClient() -> KhvolClient {
        KhvolClient(
            configDir: AppPaths.appSupportURL,
            interface: interfaceName
        )
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

    private func markMenuBarLoading() async {
        refreshTask?.cancel()
        isStatusLoading = true
        isBusy = true
        status.connection = .scanning
        await Task.yield()
    }

    func refresh(showBusy: Bool = true) async {
        guard !isBusy else { return }
        if showBusy {
            await markMenuBarLoading()
        }
        defer {
            if showBusy {
                isBusy = false
                isStatusLoading = false
            }
        }

        await applyStatusFromHelper(attemptRecovery: true)
    }

    /// Popover open: refresh interface list and status without blocking controls or rescanning.
    func preparePopover() async {
        await loadInterfacesIfNeeded()
        await refresh(showBusy: false)
    }

    private func applyStatusFromHelper(attemptRecovery: Bool) async {
        status.lastError = nil

        do {
            let json = try await makeClient().jsonStatus()
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
        } catch let err as KhvolError {
            if attemptRecovery, await recoverAfterDeviceError(err) {
                return
            }
            status.connection = .disconnected
            status.lastError = err.localizedDescription
            status.devices = []
        } catch {
            status.connection = .disconnected
            status.lastError = error.localizedDescription
        }
    }

    /// Rescan only when the speaker cache is missing (not on every transient json failure).
    private func recoverAfterDeviceError(_ err: KhvolError) async -> Bool {
        guard case .deviceError(let message) = err, shouldRescan(after: message) else { return false }
        await loadInterfaces(force: true)
        isStatusLoading = true
        isBusy = true
        defer {
            isStatusLoading = false
            isBusy = false
        }
        do {
            let count = try await makeClient().scan()
            guard count > 0 else { return false }
            let json = try await makeClient().jsonStatus()
            apply(json: json)
            status.lastError = nil
            status.connection = json.balanced ? .ready : .warning
            return true
        } catch {
            return false
        }
    }

    private func shouldRescan(after message: String) -> Bool {
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
            if status.connection == .disconnected && !interfaces.isEmpty && !isBusy {
                await refresh(showBusy: false)
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
        guard !isBusy else { return }
        cancelPendingVolume()
        config.networkInterface = name
        saveConfig()
        isStatusLoading = true
        isBusy = true
        status.lastError = nil
        defer {
            isStatusLoading = false
            isBusy = false
        }
        do {
            _ = try await makeClient().scan()
            await refreshWhileBusy()
        } catch {
            status.lastError = error.localizedDescription
            status.connection = .disconnected
        }
    }

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

        if isBusy {
            volumeCommitPendingAfterBusy = true
            return
        }
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
        volumeCommitPendingAfterBusy = false
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
        guard pendingVolumeLevel != nil, !isVolumeCommitting else { return }
        guard !isBusy else {
            volumeCommitPendingAfterBusy = true
            return
        }
        lastVolumeCommitStart = .now
        await commitPendingVolume()
    }

    private func commitPendingVolume() async {
        guard let levelToCommit = pendingVolumeLevel else { return }

        let success = await executeVolumeLevelMutation {
            try await $0.setLevel(levelToCommit)
        }

        if success {
            if pendingVolumeLevel == levelToCommit {
                pendingVolumeLevel = nil
            } else if pendingVolumeLevel != nil {
                lastVolumeCommitStart = .now
                await commitPendingVolume()
            }
        } else {
            if pendingVolumeLevel != nil {
                scheduleTrailingTask()
            }
        }
    }

    @discardableResult
    private func executeVolumeLevelMutation(
        _ body: (KhvolClient) async throws -> KhvolJSONStatus
    ) async -> Bool {
        guard !isVolumeCommitting else { return false }

        isVolumeCommitting = true
        isBusy = true

        defer {
            isVolumeCommitting = false
            isBusy = false
            flushVolumeCommitAfterBusyIfNeeded()
        }

        do {
            let json = try await body(makeClient())
            status.lastError = nil
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
            return true
        } catch let err as KhvolError {
            lastInterfacesLoad = nil
            status.lastError = err.localizedDescription
            status.connection = .disconnected
            return false
        } catch {
            lastInterfacesLoad = nil
            status.lastError = error.localizedDescription
            status.connection = .disconnected
            return false
        }
    }

    private func flushVolumeCommitAfterBusyIfNeeded() {
        guard volumeCommitPendingAfterBusy, pendingVolumeLevel != nil else {
            volumeCommitPendingAfterBusy = false
            return
        }
        volumeCommitPendingAfterBusy = false
        scheduleThrottledCommit()
    }

    private func runMutation(_ body: (KhvolClient) async throws -> KhvolJSONStatus) async {
        guard !isBusy else { return }
        await markMenuBarLoading()
        defer {
            isBusy = false
            isStatusLoading = false
            flushVolumeCommitAfterBusyIfNeeded()
        }
        do {
            let json = try await body(makeClient())
            status.lastError = nil
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
        } catch let err as KhvolError {
            lastInterfacesLoad = nil
            status.lastError = err.localizedDescription
            status.connection = .disconnected
        } catch {
            lastInterfacesLoad = nil
            status.lastError = error.localizedDescription
            status.connection = .disconnected
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
        refreshTask = Task { await refresh(showBusy: true) }
    }

    private func refreshWhileBusy() async {
        status.lastError = nil

        do {
            let client = makeClient()
            let json = try await client.jsonStatus()
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
        } catch let err as KhvolError {
            status.connection = .disconnected
            status.lastError = err.localizedDescription
            status.devices = []
        } catch {
            status.connection = .disconnected
            status.lastError = error.localizedDescription
        }
    }
}
