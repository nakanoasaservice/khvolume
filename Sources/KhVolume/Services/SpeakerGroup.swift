import Foundation

/// The speakers as one unit: every request goes to all of them.
protocol SpeakerControlling: Sendable {
    /// Reads every speaker's output on `interface`. Speakers come from the last scan; they are
    /// searched for again when there was none, or when `rescan` is set.
    func connect(interface: String?, rescan: Bool) async throws(SpeakerError) -> [SpeakerOutput]
    func setLevel(_ level: Double) async throws(SpeakerError) -> [SpeakerOutput]
    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput]
    /// Drops the open connections (e.g. after a network change); the next request reconnects.
    func disconnect() async
}

/// Owns the connections to the speakers and what they last reported.
///
/// Requests to different speakers run in parallel. Callers run one operation at a time.
actor SpeakerGroup: SpeakerControlling {
    static let maxLevel = 120.0

    typealias Scan = @Sendable (_ interface: String) async -> [Speaker]

    private let directory: SpeakerDirectory
    private let scan: Scan
    private let port: UInt16
    private let timeout: TimeInterval

    private var interface: String?
    private var links: [SpeakerLink] = []
    private var outputs: [SpeakerOutput] = []

    init(
        directory: SpeakerDirectory = SpeakerDirectory(),
        port: UInt16 = 45,
        timeout: TimeInterval = 3,
        scan: @escaping Scan = { await SSCBrowser.scan(interface: $0) }
    ) {
        self.directory = directory
        self.port = port
        self.timeout = timeout
        self.scan = scan
    }

    func connect(interface: String?, rescan: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        guard let interface, !interface.isEmpty else { throw .noInterface }
        if rescan || interface != self.interface || links.isEmpty {
            try await openLinks(on: interface, rescan: rescan)
        }
        return try await readOutputs()
    }

    func setLevel(_ level: Double) async throws(SpeakerError) -> [SpeakerOutput] {
        try await apply(SSCMessage.setLevel(min(max(level, 0), Self.maxLevel)))
    }

    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        try await apply(SSCMessage.setMuted(muted))
    }

    func disconnect() {
        links.forEach { $0.close() }
    }

    private func openLinks(on interface: String, rescan: Bool) async throws(SpeakerError) {
        disconnect()
        links = []
        outputs = []
        self.interface = interface

        var speakers = rescan ? [] : directory.load()
        if speakers.isEmpty {
            speakers = await scan(interface)
            guard !speakers.isEmpty else { throw .noSpeakersFound(interface: interface) }
            directory.store(speakers)
        }
        links = speakers.map { SpeakerLink(speaker: $0, interface: interface, port: port, timeout: timeout) }
    }

    private func readOutputs() async throws(SpeakerError) -> [SpeakerOutput] {
        var read: [SpeakerOutput] = []
        for reply in try await sendToAll(SSCMessage.outputQuery) {
            guard let output = SSCMessage.parseOutput(reply.text), let level = output.level else {
                throw .unexpectedReply(speaker: reply.name)
            }
            read.append(SpeakerOutput(id: reply.id, name: reply.name, level: level, muted: output.mute ?? false))
        }
        outputs = read
        return read
    }

    /// Sends a set message. A speaker answers a set with the value it applied, which updates what
    /// is known about it without a second round trip; any other answer falls back to reading.
    private func apply(_ message: String) async throws(SpeakerError) -> [SpeakerOutput] {
        var updated = outputs
        for reply in try await sendToAll(message) {
            guard let index = updated.firstIndex(where: { $0.id == reply.id }),
                  let applied = SSCMessage.parseOutput(reply.text),
                  applied.level != nil || applied.mute != nil
            else { return try await readOutputs() }
            if let level = applied.level { updated[index].level = level }
            if let mute = applied.mute { updated[index].muted = mute }
        }
        outputs = updated
        return updated
    }

    /// Sends `message` to every speaker in parallel. Replies come back in speaker order.
    private func sendToAll(_ message: String) async throws(SpeakerError) -> [SpeakerLink.Reply] {
        let links = self.links
        guard !links.isEmpty else {
            if let interface { throw .noSpeakersFound(interface: interface) }
            throw .noInterface
        }
        let results = await withTaskGroup(of: (Int, Result<SpeakerLink.Reply, SpeakerError>).self) { group in
            for (index, link) in links.enumerated() {
                group.addTask { (index, await link.send(message)) }
            }
            var collected = [Result<SpeakerLink.Reply, SpeakerError>?](repeating: nil, count: links.count)
            for await (index, result) in group { collected[index] = result }
            return collected.compactMap { $0 }
        }
        return try results.map { result throws(SpeakerError) in try result.get() }
    }
}
