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
        // Free the speakers' connection slots while asleep; requests reconnect after wake.
        // No quit handler is needed: the kernel closes BSD sockets when the process exits.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in
            SSCSpeakerPool.shared.closeAll()
        }
    }
}
