import Observation

/// Manages the LaunchAtLogin preference — owns the error-message state
/// and delegates to LaunchAtLogin to read/write SMAppService.
/// Injectable interface for LaunchAtLogin coordination — isolates SMAppService calls from SpeakerStore.
@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    /// Error message from the last `apply` call, if any.
    var errorMessage: String? { get }
    /// Reads live SMAppService state and corrects `config` if it diverged.
    func reconcile(config: inout AppConfig)
    /// Writes `config.launchAtLogin` to SMAppService and updates `config` and `errorMessage`.
    func apply(config: inout AppConfig)
}

@Observable
@MainActor
final class LaunchAtLoginCoordinator: LaunchAtLoginManaging {
    private(set) var errorMessage: String?

    /// Reads the live SMAppService state and reconciles it with `config`.
    /// Saves to disk when a correction is needed.
    func reconcile(config: inout AppConfig) {
        let enabled = LaunchAtLogin.serviceIsEnabled
        guard config.launchAtLogin != enabled else { return }
        config.launchAtLogin = enabled
        AppPaths.saveConfig(config)
    }

    /// Applies `config.launchAtLogin` to SMAppService.
    /// Updates `config` and `errorMessage` based on the result.
    /// Saves to disk on failure.
    func apply(config: inout AppConfig) {
        let result = LaunchAtLogin.setEnabled(config.launchAtLogin)
        switch result {
        case .success:
            errorMessage = nil
            config.launchAtLogin = LaunchAtLogin.serviceIsEnabled
        case .unavailable(let message):
            errorMessage = message
            config.launchAtLogin = false
            AppPaths.saveConfig(config)
        }
    }
}
