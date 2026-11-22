import Foundation
import Network
import os

/// Finds SSC devices (`_ssc._tcp`) on one interface via Bonjour.
enum SSCBrowser {
    /// Returns the speakers seen on `interface`, sorted by mDNS service name.
    static func scan(interface: String, browseDuration: Duration = .seconds(3)) async -> [Speaker] {
        let services = await browse(interface: interface, duration: browseDuration)
        return await withTaskGroup(of: Speaker?.self) { group in
            for service in services {
                group.addTask {
                    await resolve(service, interface: interface).map { Speaker(id: service.name, address: $0) }
                }
            }
            var found: [Speaker] = []
            for await speaker in group {
                if let speaker { found.append(speaker) }
            }
            return found.sorted { $0.id < $1.id }
        }
    }

    /// A browsed service and, when Bonjour reported it, the selected interface it was seen on.
    private struct Service {
        let name: String
        let endpoint: NWEndpoint
        let interface: NWInterface?
    }

    private static func browse(interface: String, duration: Duration) async -> [Service] {
        let browser = NWBrowser(for: .bonjour(type: "_ssc._tcp", domain: "local."), using: NWParameters())
        let results = OSAllocatedUnfairLock(initialState: Set<NWBrowser.Result>())
        browser.browseResultsChangedHandler = { latest, _ in results.withLock { $0 = latest } }
        browser.start(queue: .global(qos: .userInitiated))
        try? await Task.sleep(for: duration)
        browser.cancel()

        return results.withLock { $0 }.compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            // The speaker port has no route, so NWBrowser can't be pinned to it; filter instead.
            let selected = result.interfaces.first { $0.name == interface }
            guard result.interfaces.isEmpty || selected != nil else { return nil }
            return Service(name: name, endpoint: result.endpoint, interface: selected)
        }
    }

    /// Resolves on the selected interface. A service seen on several interfaces (Ethernet and Wi-Fi
    /// on one LAN) otherwise resolves on whichever the system prefers, and that address is rejected.
    /// Falls back to an unpinned resolve in case the interface can't be required.
    private static func resolve(_ service: Service, interface: String) async -> String? {
        if let selected = service.interface, case .service(let name, let type, let domain, _) = service.endpoint {
            let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: selected)
            if let address = await resolve(endpoint, requiring: selected, interface: interface) { return address }
        }
        return await resolve(service.endpoint, requiring: nil, interface: interface)
    }

    /// Resolves a Bonjour service to its IPv6 address. Uses a UDP "connection", which resolves the
    /// endpoint without sending anything, so no TCP slot on the speaker is used.
    private static func resolve(
        _ endpoint: NWEndpoint, requiring required: NWInterface?, interface: String, timeout: TimeInterval = 3
    ) async -> String? {
        let parameters = NWParameters.udp
        parameters.requiredInterface = required
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v6
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let queue = DispatchQueue(label: "com.khvolume.ssc.resolve")
        let address: String? = await withCheckedContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (String?) -> Void = { value in
                let alreadyFinished = finished.withLock { done in
                    defer { done = true }
                    return done
                }
                guard !alreadyFinished else { return }
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
