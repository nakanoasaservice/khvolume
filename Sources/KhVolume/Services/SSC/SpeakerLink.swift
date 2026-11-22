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
        /// What `text` says about the speaker's own output; nil when it says nothing about it.
        let output: SSCMessage.Output?
    }

    /// Builds a message about the speaker's own output, which not every device keeps at the same node.
    typealias Message = @Sendable (SSCMessage.OutputNode) -> String

    let speaker: Speaker
    private let socket: SSCSocket
    private let queue: DispatchQueue
    /// Device name from SSC, asked once for the life of the link.
    private var name: String?
    /// Where the device keeps its own output, worked out once for the life of the link.
    private var node: SSCMessage.OutputNode?

    init(speaker: Speaker, interface: String, port: UInt16 = 45, timeout: TimeInterval = 3) {
        self.speaker = speaker
        socket = SSCSocket(address: speaker.address, interface: interface, port: port, timeout: timeout)
        queue = DispatchQueue(label: "com.khvolume.ssc.\(speaker.address)")
    }

    func send(_ message: @escaping Message) async -> Result<Reply, SpeakerError> {
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

    private func sendNow(_ message: Message) throws(SpeakerError) -> Reply {
        if name == nil {
            name = SSCMessage.parseDeviceName(try exchange(SSCMessage.deviceNameQuery)) ?? speaker.address
        }
        if node == nil {
            node = try outputNode()
        }
        let text = try exchange(message(node!))
        if SSCMessage.isError(text) { throw .rejected(speaker: name!, reply: text) }
        return Reply(id: speaker.id, name: name!, text: text, output: SSCMessage.parseOutput(text, node: node!))
    }

    /// Asks the device what it is. A device that does not say is treated as a plain speaker.
    /// The fields are asked one at a time, as khtool does.
    private func outputNode() throws(SpeakerError) -> SSCMessage.OutputNode {
        let product = SSCMessage.parseProduct(try exchange(SSCMessage.productQuery))
        // Only a KH 750's node depends on its firmware.
        let version = product == SSCMessage.OutputNode.kh750
            ? SSCMessage.parseVersion(try exchange(SSCMessage.versionQuery))
            : nil
        return SSCMessage.OutputNode(product: product, version: version)
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
            // The popover only says "not responding"; the cause (timeout, no route…) goes to the log.
            NSLog("SSC %@: %@", speaker.id, String(describing: error))
            socket.close()
            throw .unreachable(speaker: name ?? speaker.address)
        }
    }
}
