import Foundation

/// Abstracts HotkeyManager for dependency injection and testability.
@MainActor
protocol HotkeyService: AnyObject {
    func register()
}

extension HotkeyManager: HotkeyService {}
