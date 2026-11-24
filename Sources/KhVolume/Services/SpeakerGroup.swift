import Foundation

/// The speakers as one unit: every request goes to all of them.
protocol SpeakerGroup: Sendable {
    /// Reads every speaker's output on `interface`. Speakers come from the last scan; they are
    /// searched for again when there was none, or when `rescan` is set.
    func connect(interface: String?, rescan: Bool) async throws(SpeakerError) -> [SpeakerOutput]
    func setLevel(_ level: Double) async throws(SpeakerError) -> [SpeakerOutput]
    func setMuted(_ muted: Bool) async throws(SpeakerError) -> [SpeakerOutput]
    /// Drops the open connections (e.g. after a network change); the next request reconnects.
    func disconnect() async
}
