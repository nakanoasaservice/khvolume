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
    /// Preview level before hotkey burst commits (shown in the menu bar immediately).
    var pendingVolumeLevel: Double?

    private var refreshTask: Task<Void, Never>?
    private var hotkeyCommitTask: Task<Void, Never>?
    private var hotkeyManager: HotkeyManager?
    private var hasStartedUp = false
    /// When a hotkey arrives during apply, commit after the current operation finishes.
    private var hotkeyCommitPendingAfterBusy = false
    private let hotkeyDebounceNanos: UInt64 = 400_000_000

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
        await loadInterfaces()
        scheduleRefresh()
    }

    var interfaceName: String {
        config.networkInterface ?? "en15"
    }

    /// Current level for UI, including uncommitted hotkey preview.
    var previewAverageLevel: Double {
        pendingVolumeLevel ?? status.averageLevel
    }

    /// Menu bar label (uncommitted value while hotkey preview is active).
    var menuBarLabel: String {
        if let pending = pendingVolumeLevel, !isBusy {
            return "\(Int(pending.rounded()))"
        }
        return status.menuBarTitle
    }

    /// Menu bar label while applying to speakers (single glyph, no extra width).
    var menuBarApplyingText: String { "↻" }

    private func makeClient() -> KhvolClient {
        KhvolClient(
            configDir: AppPaths.appSupportURL,
            interface: interfaceName,
            maxLevel: config.effectiveMax,
            step: config.volumeStep,
            force: config.allowForceOnMismatch
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

    func refresh() async {
        guard !isBusy else { return }
        await markMenuBarLoading()
        defer { isBusy = false }

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

    func loadInterfaces() async {
        do {
            interfaces = try await makeClient().interfaces()
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
        let clamped = min(config.effectiveMax, max(0, level))
        await runMutation { try await $0.setLevel(clamped) }
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
        if delta > 0 && status.levelMismatch && !config.allowForceOnMismatch {
            status.lastError = "Left and right levels do not match"
            return false
        }
        return true
    }

    private func applyHotkeyVolumePreview(delta: Double) {
        let base = pendingVolumeLevel ?? status.averageLevel
        pendingVolumeLevel = min(config.effectiveMax, max(0, base + delta))
        status.lastError = nil
    }

    func toggleMute() async {
        cancelPendingHotkeyVolume()
        await runMutation { try await $0.toggleMute() }
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
        guard let level = pendingVolumeLevel else { return }
        await runMutation { try await $0.setLevel(level) }
        pendingVolumeLevel = nil
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
            switch err {
            case .mismatch:
                status.connection = .warning
            default:
                status.connection = .disconnected
            }
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
        refreshTask = Task { await refresh() }
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
