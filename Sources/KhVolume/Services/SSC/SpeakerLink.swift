import Foundation

/// The long-lived SSC connection to one speaker.
///
/// The connection opens on first use and is reused for later requests; a request that fails on a
/// reused connection is retried once on a fresh one. Requests run on the link's own serial queue,
/// so they never interleave and replies come back in the order the requests were made.
final class SpeakerLink: @unchecked Sendable {
    struct Reply: Equatable, Sendable {
        /// The speaker's mDNS service name.
        let id: String
        /// SSC device name.
        let name: String
        let text: String
    }

    let speaker: Speaker
    private let socket: SSCSocket
    private let queue: DispatchQueue
    /// Device name from SSC, asked once for the life of the link.
    private var name: String?

    init(speaker: Speaker, interface: String, port: UInt16 = 45, timeout: TimeInterval = 3) {
        self.speaker = speaker
        socket = SSCSocket(address: speaker.address, interface: interface, port: port, timeout: timeout)
        queue = DispatchQueue(label: "com.khvolume.ssc.\(speaker.address)")
    }

    func send(_ message: String) async -> Result<Reply, SpeakerError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { () throws(SpeakerError) in try self.sendNow(message) })
            }
        }
    }

    /// Closes the connection; the next request reconnects.
    func close() {
        queue.async { self.socket.close() }
    }

    private func sendNow(_ message: String) throws(SpeakerError) -> Reply {
        if name == nil {
            name = SSCMessage.parseDeviceName(try exchange(SSCMessage.deviceNameQuery)) ?? speaker.address
        }
        let text = try exchange(message)
        if SSCMessage.isError(text) { throw .rejected(speaker: name!, reply: text) }
        return Reply(id: speaker.id, name: name!, text: text)
    }

    private func exchange(_ message: String) throws(SpeakerError) -> String {
        if socket.isOpen, let reply = try? socket.request(message) {
            return reply
        }
        // Not connected yet, or the reused connection went stale (speaker rebooted, cable replugged…).
        do {
            try socket.open()
            return try socket.request(message)
        } catch {
            socket.close()
            throw .unreachable(speaker: name ?? speaker.address)
        }
    }
}
