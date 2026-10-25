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
    @NSApplicationDelegateAdaptor(KhVolumeAppDelegate.self) private var appDelegate
    @State private var store = SpeakerStore()

    var body: some Scene {
        MenuBarExtra {
            VolumePopoverView(store: store)
        } label: {
            MenuBarStatusLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SoundSettingsView(store: store)
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
