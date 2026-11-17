import Foundation
import Network

/// Finds SSC devices (`_ssc._tcp`) on one interface via Bonjour.
enum SSCBrowser {
    /// Returns `[mDNS service name: IPv6 address]` for the devices seen on `interface`.
    static func scan(interface: String, browseDuration: Duration = .seconds(3)) async -> [String: String] {
        let services = await browse(interface: interface, duration: browseDuration)
        return await withTaskGroup(of: (String, String?).self) { group in
            for (name, endpoint) in services {
                group.addTask { (name, await resolve(endpoint, interface: interface)) }
            }
            var found: [String: String] = [:]
            for await (name, address) in group {
                if let address { found[name] = address }
            }
            return found
        }
    }

    private static func browse(interface: String, duration: Duration) async -> [(String, NWEndpoint)] {
        let browser = NWBrowser(for: .bonjour(type: "_ssc._tcp", domain: "local."), using: NWParameters())
        let results = LockedValue<Set<NWBrowser.Result>>([])
        browser.browseResultsChangedHandler = { latest, _ in results.set(latest) }
        browser.start(queue: .global(qos: .userInitiated))
        try? await Task.sleep(for: duration)
        browser.cancel()

        return results.get().compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            // The speaker port has no route, so NWBrowser can't be pinned to it; filter instead.
            guard result.interfaces.isEmpty || result.interfaces.contains(where: { $0.name == interface }) else {
                return nil
            }
            return (name, result.endpoint)
        }
    }

    /// Resolves a Bonjour service to its IPv6 address. Uses a UDP "connection", which resolves the
    /// endpoint without sending anything, so no TCP slot on the speaker is used.
    private static func resolve(_ endpoint: NWEndpoint, interface: String, timeout: TimeInterval = 3) async -> String? {
        let parameters = NWParameters.udp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v6
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "com.khvolume.ssc.resolve")
        let address: String? = await withCheckedContinuation { continuation in
            let finished = LockedValue(false)
            let finish: @Sendable (String?) -> Void = { value in
                guard finished.exchange(true) == false else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(ipv6Address(of: connection.currentPath?.remoteEndpoint, interface: interface))
                case .failed, .waiting, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
        return address
    }

    private static func ipv6Address(of endpoint: NWEndpoint?, interface: String) -> String? {
        guard case .hostPort(.ipv6(let ip), _) = endpoint else { return nil }
        if let scope = ip.interface, scope.name != interface { return nil }
        // Store bare addresses; the scope is added back when connecting.
        return "\(ip)".split(separator: "%").first.map(String.init)
    }
}

/// Minimal lock-protected box for state shared with Network.framework callbacks.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }

    /// Stores `newValue` and returns the previous value.
    func exchange(_ newValue: Value) -> Value {
        lock.withLock {
            let old = value
            value = newValue
            return old
        }
    }
}
