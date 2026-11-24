import SwiftUI

@main
enum KhVolumeMain {
    static func main() {
        // Unit tests run inside the app as their test host; skip the real app there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            TestHostApp.main()
        } else {
            KhVolumeApp.main()
        }
    }
}

struct KhVolumeApp: App {
    @State private var store: SpeakerStore
    @State private var loginItem = LoginItem()
    /// Kept for the life of the app; the hotkey handlers hold it weakly.
    private let hotkeys: HotkeyManager

    init() {
        let store = SpeakerStore()
        let hotkeys = HotkeyManager(store: store)
        _store = State(initialValue: store)
        self.hotkeys = hotkeys
        // Started here, not from a view, so volume and hotkeys work before the popover is opened.
        Task { @MainActor in
            hotkeys.register()
            store.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            VolumePopoverView(store: store)
        } label: {
            MenuBarStatusLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SoundSettingsView(store: store, loginItem: loginItem)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 440)
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
