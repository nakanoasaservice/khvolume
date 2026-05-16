import AppKit

@MainActor
enum KhVolumeBootstrap {
    weak static var store: SpeakerStore?
}

final class KhVolumeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await KhVolumeBootstrap.store?.startupIfNeeded()
        }
    }
}
