import Foundation
import Network

/// Abstracts NWPathMonitor for dependency injection and testability.
@MainActor
protocol NetworkPathMonitor: AnyObject {
    /// Called on MainActor whenever the network path changes.
    /// `true` means the path is satisfied (network available); `false` means lost.
    var onPathChange: (@MainActor (Bool) -> Void)? { get set }
    func start()
}

final class SystemNetworkPathMonitor: NetworkPathMonitor {
    var onPathChange: (@MainActor (Bool) -> Void)?

    private var monitor: NWPathMonitor?
    private var hasSeenCurrentPath = false
    private let queue = DispatchQueue(label: "com.khvolume.pathmonitor", qos: .utility)

    func start() {
        let monitor = NWPathMonitor()
        hasSeenCurrentPath = false
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                // The monitor first reports the path as it is when it starts; that is not a change.
                guard hasSeenCurrentPath else {
                    hasSeenCurrentPath = true
                    return
                }
                onPathChange?(satisfied)
            }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
