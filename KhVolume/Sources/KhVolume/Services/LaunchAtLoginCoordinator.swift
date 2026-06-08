import Observation

/// Manages the LaunchAtLogin preference — owns the error-message state
/// and delegates to LaunchAtLogin to read/write SMAppService.
@Observable
@MainActor
final class LaunchAtLoginCoordinator {
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
