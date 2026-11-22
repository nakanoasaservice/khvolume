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
        let level = min(max(level, 0), Self.maxLevel)
        return try await apply { SSCMessage.setLevel(level, node: $0) }
    }

    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput] {
        try await apply { SSCMessage.setMuted(muted, node: $0) }
    }

    func disconnect() {
        links.forEach { $0.close() }
    }

    private func openLinks(on interface: String, rescan: Bool) async throws(SpeakerError) {
        disconnect()
        links = []
        outputs = []
        self.interface = interface

        func link(_ speaker: Speaker) -> SpeakerLink {
            SpeakerLink(speaker: speaker, interface: interface, port: port, timeout: timeout)
        }
        var links = (rescan ? [] : directory.load()).map(link)
        if links.isEmpty {
            links = await speakersOnly(scan(interface).map(link))
            guard !links.isEmpty else { throw .noSpeakersFound(interface: interface) }
            directory.store(links.map(\.speaker))
        }
        self.links = links
    }

    /// Other devices announce SSC too. One that rejects a question about its output is not a
    /// speaker; it is left out, so that it cannot fail every request to the group.
    private func speakersOnly(_ found: [SpeakerLink]) async -> [SpeakerLink] {
        let answers = await send({ SSCMessage.outputQuery($0) }, to: found)
        return zip(found, answers).compactMap { link, answer in
            guard case .failure(.rejected) = answer else { return link }
            link.close()
            return nil
        }
    }

    private func readOutputs() async throws(SpeakerError) -> [SpeakerOutput] {
        var read: [SpeakerOutput] = []
        for reply in try await sendToAll({ SSCMessage.outputQuery($0) }) {
            guard let output = reply.output, let level = output.level else {
                throw .unexpectedReply(speaker: reply.name)
            }
            read.append(SpeakerOutput(id: reply.id, name: reply.name, level: level, muted: output.mute ?? false))
        }
        outputs = read
        return read
    }

    /// Sends a set message. A speaker answers a set with the value it applied, which updates what
    /// is known about it without a second round trip; any other answer falls back to reading.
    private func apply(_ message: @escaping SpeakerLink.Message) async throws(SpeakerError) -> [SpeakerOutput] {
        var updated = outputs
        for reply in try await sendToAll(message) {
            guard let index = updated.firstIndex(where: { $0.id == reply.id }),
                  let applied = reply.output,
                  applied.level != nil || applied.mute != nil
            else { return try await readOutputs() }
            if let level = applied.level { updated[index].level = level }
            if let mute = applied.mute { updated[index].muted = mute }
        }
        outputs = updated
        return updated
    }

    /// Sends `message` to every speaker in parallel. Replies come back in speaker order.
    private func sendToAll(_ message: @escaping SpeakerLink.Message) async throws(SpeakerError) -> [SpeakerLink.Reply] {
        guard !links.isEmpty else {
            if let interface { throw .noSpeakersFound(interface: interface) }
            throw .noInterface
        }
        return try await send(message, to: links).map { result throws(SpeakerError) in try result.get() }
    }

    /// Sends `message` over every one of `links` in parallel. Answers come back in link order.
    private func send(
        _ message: @escaping SpeakerLink.Message, to links: [SpeakerLink]
    ) async -> [Result<SpeakerLink.Reply, SpeakerError>] {
        await withTaskGroup(of: (Int, Result<SpeakerLink.Reply, SpeakerError>).self) { group in
            for (index, link) in links.enumerated() {
                group.addTask { (index, await link.send(message)) }
            }
            var collected = [Result<SpeakerLink.Reply, SpeakerError>?](repeating: nil, count: links.count)
            for await (index, result) in group { collected[index] = result }
            return collected.compactMap { $0 }
        }
    }
}
