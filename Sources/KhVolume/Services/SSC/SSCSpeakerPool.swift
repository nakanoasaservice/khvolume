import Foundation

/// Long-lived SSC connections, one per speaker, shared by every `KhvolClient`.
///
/// Connections open on first use and are reused for later requests; a request that fails on a
/// reused connection is retried once on a fresh one. Each speaker has its own serial queue, so
/// requests to one speaker never interleave while different speakers are queried in parallel.
final class SSCSpeakerPool: @unchecked Sendable {
    static let shared = SSCSpeakerPool()

    struct Reply: Equatable, Sendable {
        let name: String
        let reply: String
    }

    private let port: UInt16
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var interface: String?
    private var speakers: [String: Speaker] = [:]

    init(port: UInt16 = 45, timeout: TimeInterval = 3) {
        self.port = port
        self.timeout = timeout
    }

    /// Sends `message` to every speaker in parallel. Replies come back in `addresses` order.
    func send(_ message: String, to addresses: [String], interface: String) async throws(KhvolError) -> [Reply] {
        let targets = speakers(for: addresses, interface: interface)
        let results = await withTaskGroup(of: (Int, Result<Reply, KhvolError>).self) { group in
            for (index, speaker) in targets.enumerated() {
                group.addTask { (index, await speaker.send(message)) }
            }
            var collected = [Result<Reply, KhvolError>?](repeating: nil, count: targets.count)
            for await (index, result) in group { collected[index] = result }
            return collected.compactMap { $0 }
        }
        return try results.map { result throws(KhvolError) in try result.get() }
    }

    /// Closes every connection; the next request reconnects.
    func closeAll() {
        lock.withLock {
            speakers.values.forEach { $0.close() }
            speakers.removeAll()
        }
    }

    /// Number of speakers with a connection object (open or not); for tests.
    var speakerCount: Int { lock.withLock { speakers.count } }

    private func speakers(for addresses: [String], interface: String) -> [Speaker] {
        lock.withLock {
            if self.interface != interface {
                speakers.values.forEach { $0.close() }
                speakers.removeAll()
                self.interface = interface
            }
            let wanted = Set(addresses)
            for (address, speaker) in speakers where !wanted.contains(address) {
                speaker.close()
                speakers[address] = nil
            }
            return addresses.map { address in
                if let existing = speakers[address] { return existing }
                let speaker = Speaker(socket: SSCSocket(address: address, interface: interface, port: port, timeout: timeout))
                speakers[address] = speaker
                return speaker
            }
        }
    }
}

private final class Speaker: @unchecked Sendable {
    private let socket: SSCSocket
    private let queue: DispatchQueue
    /// Device name from SSC, cached for the life of the connection object.
    private var name: String?

    init(socket: SSCSocket) {
        self.socket = socket
        queue = DispatchQueue(label: "com.khvolume.ssc.\(socket.address)")
    }

    func send(_ message: String) async -> Result<SSCSpeakerPool.Reply, KhvolError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { () throws(KhvolError) in try self.sendNow(message) })
            }
        }
    }

    func close() {
        queue.async { self.socket.close() }
    }

    private func sendNow(_ message: String) throws(KhvolError) -> SSCSpeakerPool.Reply {
        if name == nil {
            name = SSCMessage.parseDeviceName(try exchange(SSCMessage.deviceNameQuery)) ?? socket.address
        }
        return SSCSpeakerPool.Reply(name: name!, reply: try exchange(message))
    }

    private func exchange(_ message: String) throws(KhvolError) -> String {
        if socket.isOpen, let reply = try? socket.request(message) {
            return reply
        }
        // Not connected yet, or the reused connection went stale (speaker rebooted, cable replugged…).
        do {
            try socket.open()
        } catch {
            throw .commandFailed("device \(socket.address) is not online")
        }
        do {
            return try socket.request(message)
        } catch {
            socket.close()
            throw .commandFailed("no response from \(socket.address)")
        }
    }
}
