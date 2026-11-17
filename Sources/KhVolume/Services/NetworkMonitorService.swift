import Foundation
import Network

/// Abstracts NWPathMonitor for dependency injection and testability.
@MainActor
protocol NetworkMonitorService: AnyObject {
    /// Called on MainActor whenever the network path changes.
    /// `true` means the path is satisfied (network available); `false` means lost.
    var onPathChange: (@MainActor (Bool) -> Void)? { get set }
    func start()
    func stop()
}

final class SystemNetworkMonitorService: NetworkMonitorService {
    var onPathChange: (@MainActor (Bool) -> Void)?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.khvolume.pathmonitor", qos: .utility)

    func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.onPathChange?(satisfied)
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
