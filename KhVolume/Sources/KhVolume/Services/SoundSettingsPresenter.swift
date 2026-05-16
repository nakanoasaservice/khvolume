import AppKit
import SwiftUI

/// Brings the sound settings window to the front (for MenuBarExtra).
@MainActor
enum SoundSettingsPresenter {
    private static let windowTitle = "KH Volume Sound Settings"
    private static var fallbackPanel: NSPanel?
    private static let windowDelegate = SettingsWindowDelegate()

    /// Called from the popover: open via `openWindow`, raise, or fall back to NSPanel.
    static func present(store: SpeakerStore, openWindow: OpenWindowAction) {
        dismissMenuBarPopover()
        openWindow(id: "sound-settings")

        Task { @MainActor in
            for delayMs in [80, 200, 400] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                if raiseExistingSettingsWindow() {
                    return
                }
            }
            presentFallbackPanel(store: store)
        }
    }

    @discardableResult
    static func raiseExistingSettingsWindow() -> Bool {
        guard let window = findSettingsWindow() else { return false }

        elevateApplicationForWindow()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate()

        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private static func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == windowTitle && $0.isVisible }
            ?? NSApp.windows.first { $0.title == windowTitle }
    }

    private static func presentFallbackPanel(store: SpeakerStore) {
        let win = fallbackPanel ?? makeFallbackPanel()
        updateContent(win, store: store)

        elevateApplicationForWindow()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate()

        win.level = .floating
        win.orderFrontRegardless()
        win.makeKeyAndOrderFront(nil)
    }

    private static func dismissMenuBarPopover() {
        NSApp.keyWindow?.orderOut(nil)
        for window in NSApp.windows {
            if let fallbackPanel, window === fallbackPanel { continue }
            let name = String(describing: type(of: window))
            if name.contains("Popover") || name.contains("StatusBar") {
                window.orderOut(nil)
            }
        }
    }

    private static func elevateApplicationForWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private static func makeFallbackPanel() -> NSPanel {
        let win = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = windowTitle
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = false
        win.collectionBehavior = [.moveToActiveSpace, .canJoinAllSpaces, .fullScreenAuxiliary]
        win.delegate = windowDelegate
        win.center()
        fallbackPanel = win
        return win
    }

    private static func updateContent(_ win: NSPanel, store: SpeakerStore) {
        let rootView = SoundSettingsView(store: store)
            .frame(width: 420, height: 400)
        win.contentView = NSHostingView(rootView: rootView)
        if !win.isVisible {
            win.center()
        }
    }
}

@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let title = "KH Volume Sound Settings"
        let anyOpen = NSApp.windows.contains { $0.isVisible && $0.title == title }
        if !anyOpen, NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
