import AppKit
import SwiftUI

/// Brings the preferences window to the front (for MenuBarExtra).
@MainActor
enum SoundSettingsPresenter {
    static func present(openSettings: OpenSettingsAction) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate()
    }

    static func settingsWindowDidClose() {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
