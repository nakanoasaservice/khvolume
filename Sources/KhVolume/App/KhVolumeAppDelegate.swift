import AppKit

final class KhVolumeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
