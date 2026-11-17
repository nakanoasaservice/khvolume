import Darwin
import Foundation

/// Minimal SSC device on [::1]:<random port> for pool tests. Replies to each CRLF-terminated line
/// with `reply(line)` and records connections and requests.
final class FakeSSCServer: @unchecked Sendable {
    let port: UInt16
    private let listener: Int32
    private let lock = NSLock()
    private var clients: [Int32] = []
    private var _accepted = 0
    private var _requests: [String] = []
    private let reply: @Sendable (String) -> String

    init(reply: @escaping @Sendable (String) -> String = FakeSSCServer.defaultReply) throws {
        self.reply = reply
        let listener = socket(AF_INET6, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var on: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_addr = in6addr_loopback
        addr.sin6_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bound == 0, listen(listener, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        self.listener = listener
        port = UInt16(bigEndian: addr.sin6_port)
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    deinit { stop() }

    static let defaultReply: @Sendable (String) -> String = { line in
        if line.contains(#""name":null"#) { return #"{"device":{"name":"Fake"}}"# }
        if line.contains(#""level":null"#) { return #"{"audio":{"out":{"level":50.0,"mute":false}}}"# }
        return line
    }

    var acceptedCount: Int { lock.withLock { _accepted } }
    var openCount: Int { lock.withLock { clients.count } }
    var requests: [String] { lock.withLock { _requests } }

    /// Closes every client connection, as a rebooting speaker would.
    func dropClients() {
        lock.withLock {
            clients.forEach { shutdown($0, SHUT_RDWR) }
        }
    }

    func stop() {
        shutdown(listener, SHUT_RDWR)
        close(listener)
        dropClients()
    }

    /// Polls `condition` for up to `timeout`; for asynchronous closes.
    func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(10_000)
        }
        return condition()
    }

    private func acceptLoop() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            lock.withLock {
                clients.append(client)
                _accepted += 1
            }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { recv(client, $0.baseAddress, $0.count, 0) }
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...newline)
                lock.withLock { _requests.append(line) }
                let out = Array((reply(line) + "\r\n").utf8)
                _ = out.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
            }
        }
        lock.withLock { clients.removeAll { $0 == client } }
        close(client)
    }
}
