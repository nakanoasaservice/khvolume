import Foundation
import Observation

@Observable
@MainActor
final class SpeakerStore {
    var config: AppConfig
    var status = SpeakerStatus()
    var interfaces: [NetworkInterfaceInfo] = []
    var isBusy = false
    var launchAtLoginMessage: String?
    /// Uncommitted level from hotkey preview; cleared after a successful device commit.
    var pendingVolumeLevel: Double?

    private var refreshTask: Task<Void, Never>?
    private var hotkeyCommitTask: Task<Void, Never>?
    private var hotkeyManager: HotkeyManager?
    private let volumeHUD = VolumeHUDController()
    private var hasStartedUp = false
    private var lastInterfacesLoad: Date?
    /// When a hotkey arrives during apply, commit after the current operation finishes.
    private var hotkeyCommitPendingAfterBusy = false
    private var isHotkeyVolumeCommitting = false
    private let hotkeyDebounceNanos: UInt64 = 400_000_000
    private let interfacesReloadInterval: TimeInterval = 60

    init() {
        config = AppPaths.loadConfig()
        KhVolumeBootstrap.store = self
        volumeHUD.configure(store: self)
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

    var isVolumeCommitting: Bool { isHotkeyVolumeCommitting }

    var blocksVolumeIncrease: Bool {
        status.levelMismatch && !config.allowForceOnMismatch
    }

    var isVolumeSliderDisabled: Bool {
        status.isMuted || isBusy
    }

    private func clampVolume(_ level: Double) -> Double {
        min(config.effectiveMax, max(0, level))
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
            if showBusy { isBusy = false }
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
        isBusy = true
        defer { isBusy = false }
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
        config.networkInterface = name
        saveConfig()
        isBusy = true
        status.lastError = nil
        defer { isBusy = false }
        do {
            _ = try await makeClient().scan()
            await refreshWhileBusy()
        } catch {
            status.lastError = error.localizedDescription
            status.connection = .disconnected
        }
    }

    func setLevel(_ level: Double) async {
        cancelPendingHotkeyVolume()
        let clamped = clampVolume(level)
        await executeVolumeLevelMutation(showMenuBarLoading: true) {
            try await $0.setLevel(clamped)
        }
    }

    /// Hotkeys: immediate preview, then debounced set commit (tap, burst, and hold).
    func adjustLevelByHotkey(delta: Double) {
        guard hotkeyVolumeChangeAllowed(delta: delta) else { return }

        applyHotkeyVolumePreview(delta: delta)

        if isBusy {
            hotkeyCommitPendingAfterBusy = true
            return
        }
        scheduleHotkeyCommit()
    }

    private func hotkeyVolumeChangeAllowed(delta: Double) -> Bool {
        if delta > 0 && blocksVolumeIncrease {
            status.lastError = "Left and right levels do not match"
            return false
        }
        return true
    }

    private func applyHotkeyVolumePreview(delta: Double) {
        let base = pendingVolumeLevel ?? status.averageLevel
        pendingVolumeLevel = clampVolume(base + delta)
        status.lastError = nil
        volumeHUD.present()
    }

    func toggleMute() async {
        cancelPendingHotkeyVolume()
        let targetMuted = !status.isMuted
        await runMutation { try await $0.setMuted(targetMuted) }
        volumeHUD.present()
    }

    func cancelPendingHotkeyVolume() {
        hotkeyCommitTask?.cancel()
        hotkeyCommitTask = nil
        hotkeyCommitPendingAfterBusy = false
        pendingVolumeLevel = nil
    }

    private func scheduleHotkeyCommit() {
        hotkeyCommitTask?.cancel()
        hotkeyCommitTask = Task {
            try? await Task.sleep(nanoseconds: hotkeyDebounceNanos)
            guard !Task.isCancelled else { return }
            await commitPendingHotkeyVolume()
        }
    }

    private func commitPendingHotkeyVolume() async {
        guard let levelToCommit = pendingVolumeLevel else { return }

        let success = await executeVolumeLevelMutation(showMenuBarLoading: false) {
            try await $0.setLevel(levelToCommit)
        }
        guard success else {
            if pendingVolumeLevel != nil {
                scheduleHotkeyCommit()
            }
            return
        }

        if pendingVolumeLevel == levelToCommit {
            pendingVolumeLevel = nil
        } else if pendingVolumeLevel != nil {
            scheduleHotkeyCommit()
        }
    }

    @discardableResult
    private func executeVolumeLevelMutation(
        showMenuBarLoading: Bool,
        _ body: (KhvolClient) async throws -> KhvolJSONStatus
    ) async -> Bool {
        if showMenuBarLoading {
            guard !isBusy else { return false }
            await markMenuBarLoading()
        } else {
            guard !isHotkeyVolumeCommitting else { return false }
            isHotkeyVolumeCommitting = true
            isBusy = true
            volumeHUD.present()
        }

        defer {
            if !showMenuBarLoading {
                isHotkeyVolumeCommitting = false
            }
            isBusy = false
            flushHotkeyCommitAfterBusyIfNeeded()
        }

        do {
            let json = try await body(makeClient())
            status.lastError = nil
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
            return true
        } catch let err as KhvolError {
            status.lastError = err.localizedDescription
            status.connection = .disconnected
            return false
        } catch {
            status.lastError = error.localizedDescription
            status.connection = .disconnected
            return false
        }
    }

    private func flushHotkeyCommitAfterBusyIfNeeded() {
        guard hotkeyCommitPendingAfterBusy, pendingVolumeLevel != nil else {
            hotkeyCommitPendingAfterBusy = false
            return
        }
        hotkeyCommitPendingAfterBusy = false
        scheduleHotkeyCommit()
    }

    private func runMutation(_ body: (KhvolClient) async throws -> KhvolJSONStatus) async {
        guard !isBusy else { return }
        await markMenuBarLoading()
        defer {
            isBusy = false
            flushHotkeyCommitAfterBusyIfNeeded()
        }
        do {
            let json = try await body(makeClient())
            status.lastError = nil
            apply(json: json)
            status.connection = json.balanced ? .ready : .warning
        } catch let err as KhvolError {
            status.lastError = err.localizedDescription
            status.connection = .disconnected
        } catch {
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
