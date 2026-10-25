import Foundation

protocol KhvolClientProtocol: Sendable {
    func jsonStatus() async throws(KhvolError) -> KhvolJSONStatus
    func setLevel(_ level: Double) async throws(KhvolError) -> KhvolJSONStatus
    func setMuted(_ muted: Bool) async throws(KhvolError) -> KhvolJSONStatus
    func interfaces() async throws(KhvolError) -> [NetworkInterfaceInfo]
    @discardableResult func scan() async throws(KhvolError) -> Int
    /// Drops open speaker connections so the next request reconnects (e.g. after a network change).
    func resetConnections() async
}

extension KhvolClientProtocol {
    func resetConnections() async {}
}

enum KhvolError: LocalizedError {
    case commandFailed(String)
    case deviceError(String)
    case parseFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg):
            return msg
        case .deviceError(let msg):
            return msg
        case .parseFailed:
            return "Failed to parse speaker response"
        case .timedOut:
            return "Speaker did not respond in time"
        }
    }
}

/// Talks SSC to the scanned speakers in `SpeakerDirectory`, over connections kept in `SSCSpeakerPool`.
struct KhvolClient {
    static let maxLevel = 120.0

    let interface: String?
    var speakers = SpeakerDirectory()
    var pool: SSCSpeakerPool = .shared

    func jsonStatus() async throws(KhvolError) -> KhvolJSONStatus {
        let replies = try await sendToAll(SSCMessage.outputQuery)
        var readings: [(name: String, output: KhvolJSONStatus.DeviceInfo)] = []
        for reply in replies {
            guard let output = SSCMessage.parseOutput(reply.reply) else {
                throw .deviceError("\(reply.name): unexpected reply \(reply.reply)")
            }
            readings.append((reply.name, output))
        }
        return try SpeakerStatusBuilder.status(from: readings)
    }

    func setLevel(_ level: Double) async throws(KhvolError) -> KhvolJSONStatus {
        let clamped = min(max(level, 0), Self.maxLevel)
        try await sendToAll(SSCMessage.setLevel(clamped))
        return try await jsonStatus()
    }

    func setMuted(_ muted: Bool) async throws(KhvolError) -> KhvolJSONStatus {
        try await sendToAll(SSCMessage.setMuted(muted))
        return try await jsonStatus()
    }

    func interfaces() async throws(KhvolError) -> [NetworkInterfaceInfo] {
        NetworkInterfaceLister.list()
    }

    /// Browses for speakers on the configured interface and stores them in `SpeakerDirectory`.
    @discardableResult
    func scan() async throws(KhvolError) -> Int {
        let interface = try configuredInterface()
        pool.closeAll()
        let found = await SSCBrowser.scan(interface: interface)
        speakers.store(found)
        guard !found.isEmpty else { throw .deviceError("no speakers found on \(interface)") }
        return found.count
    }

    func resetConnections() async {
        pool.closeAll()
    }

    private func configuredInterface() throws(KhvolError) -> String {
        guard let interface, !interface.isEmpty else {
            throw .commandFailed("network interface not configured")
        }
        return interface
    }

    @discardableResult
    private func sendToAll(_ message: String) async throws(KhvolError) -> [SSCSpeakerPool.Reply] {
        let interface = try configuredInterface()
        let addresses = speakers.load()
        guard !addresses.isEmpty else { throw .deviceError("no speakers configured; run scan") }
        let replies = try await pool.send(message, to: addresses, interface: interface)
        if let failed = replies.first(where: { SSCMessage.isError($0.reply) }) {
            throw .deviceError("\(failed.name): \(failed.reply)")
        }
        return replies
    }
}

extension KhvolClient: KhvolClientProtocol {}
