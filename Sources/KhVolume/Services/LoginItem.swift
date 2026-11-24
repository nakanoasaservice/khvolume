import Foundation
import Observation
import ServiceManagement

/// Whether the app opens at login. The system (`SMAppService`) holds this state, so it is not
/// part of `AppConfig`.
@Observable
@MainActor
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    /// Why the last `setEnabled` failed; nil when it did not.
    private(set) var errorMessage: String?

    /// Reads the state again: it can change in System Settings while the app runs.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            let message = Self.message(for: error)
            NSLog("LoginItem error: \(message)")
            errorMessage = message
        }
        refresh()
    }

    private static func message(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == 4097 {
            return "Could not register the login item. Install a Developer ID–signed app in /Applications."
        }
        if ns.localizedDescription.localizedCaseInsensitiveContains("not permitted") {
            return "Login item registration was denied. Launch a signed \"KH Volume.app\" from /Applications."
        }
        return ns.localizedDescription
    }
}
