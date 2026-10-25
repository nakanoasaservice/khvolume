import Darwin
import Foundation

/// One TCP connection to an SSC device: a JSON line out, a JSON line back.
///
/// Uses BSD sockets rather than NWConnection on purpose: the kernel closes BSD sockets when the
/// process dies, while NWConnection flows that are never cancelled stay half-open on the speaker.
/// KH speakers accept only 4 concurrent connections, so leaked flows lock them up.
///
/// Not thread-safe; callers serialize access (see `SSCSpeakerPool`).
final class SSCSocket {
    enum Failure: Error, Equatable {
        case connect(String)
        case io(String)
        case timedOut
    }

    let address: String
    let interface: String
    let port: UInt16
    let timeout: TimeInterval

    private var fd: Int32 = -1

    init(address: String, interface: String, port: UInt16 = 45, timeout: TimeInterval = 3) {
        self.address = address
        self.interface = interface
        self.port = port
        self.timeout = timeout
    }

    deinit { close() }

    var isOpen: Bool { fd >= 0 }

    /// Link-local addresses need the interface as scope; others are used as-is (same rule as khtool).
    var scopedAddress: String {
        if address.contains("%") || !address.lowercased().hasPrefix("fe80:") { return address }
        return "\(address)%\(interface)"
    }

    func open() throws(Failure) {
        close()

        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        var result: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(scopedAddress, String(port), &hints, &result)
        guard rc == 0, let info = result else {
            throw .connect(String(cString: gai_strerror(rc)))
        }
        defer { freeaddrinfo(result) }

        let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard sock >= 0 else { throw .connect(Self.errnoMessage()) }

        var on: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        // Non-blocking so connect/send/recv can all be bounded by poll().
        _ = fcntl(sock, F_SETFL, fcntl(sock, F_GETFL) | O_NONBLOCK)

        let deadline = Date().addingTimeInterval(timeout)
        if connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen) != 0 {
            guard errno == EINPROGRESS else {
                let message = Self.errnoMessage()
                Darwin.close(sock)
                throw .connect(message)
            }
            guard Self.wait(sock, for: Int16(POLLOUT), until: deadline) else {
                Darwin.close(sock)
                throw .timedOut
            }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &length)
            if error != 0 {
                Darwin.close(sock)
                throw .connect(String(cString: strerror(error)))
            }
        }
        fd = sock
    }

    func close() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }

    /// Sends one JSON message and returns the device's single-line reply (without CRLF).
    func request(_ json: String) throws(Failure) -> String {
        guard fd >= 0 else { throw .io("not connected") }
        let deadline = Date().addingTimeInterval(timeout)
        try send(Array((json + "\r\n").utf8), until: deadline)
        return try receiveLine(until: deadline)
    }

    private func send(_ bytes: [UInt8], until deadline: Date) throws(Failure) {
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { buffer in
                Darwin.send(fd, buffer.baseAddress! + offset, bytes.count - offset, 0)
            }
            if sent > 0 {
                offset += sent
            } else if sent < 0 && (errno == EAGAIN || errno == EINTR) {
                guard Self.wait(fd, for: Int16(POLLOUT), until: deadline) else { throw .timedOut }
            } else {
                throw .io(Self.errnoMessage())
            }
        }
    }

    private func receiveLine(until deadline: Date) throws(Failure) -> String {
        var data = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while data.last != UInt8(ascii: "\n") {
            let count = chunk.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                data.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                throw .io("connection closed by device")
            } else if errno == EAGAIN || errno == EINTR {
                guard Self.wait(fd, for: Int16(POLLIN), until: deadline) else { throw .timedOut }
            } else {
                throw .io(Self.errnoMessage())
            }
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Waits for `events` on `fd`; false on timeout or poll error.
    private static func wait(_ fd: Int32, for events: Int16, until deadline: Date) -> Bool {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            var pfd = pollfd(fd: fd, events: events, revents: 0)
            let rc = poll(&pfd, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if rc > 0 { return true }
            if rc == 0 { return false }
            if errno != EINTR { return false }
        }
    }

    private static func errnoMessage() -> String {
        String(cString: strerror(errno))
    }
}
