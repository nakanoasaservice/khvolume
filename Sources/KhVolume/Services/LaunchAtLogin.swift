import Foundation
import ServiceManagement

enum LaunchAtLogin {
    enum SetResult {
        case success
        case unavailable(String)
    }

    /// Live Login Item state from SMAppService (preferred over the config file for UI).
    static var serviceIsEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) -> SetResult {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return .success
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    return .success
                }
                try SMAppService.mainApp.unregister()
            }
            return .success
        } catch {
            let message = launchAtLoginErrorMessage(error)
            NSLog("LaunchAtLogin error: \(message)")
            return .unavailable(message)
        }
    }

    private static func launchAtLoginErrorMessage(_ error: Error) -> String {
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
