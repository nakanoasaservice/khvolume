import SwiftUI

@main
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

        Window("KH Volume Sound Settings", id: "sound-settings") {
            SoundSettingsView(store: store)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 440)
    }
}
