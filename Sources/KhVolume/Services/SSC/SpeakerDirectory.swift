import Foundation

/// The speakers found by the last scan, kept in UserDefaults as `{"<mDNS name>": "<IPv6 address>", …}`
/// so the app can connect at launch without a scan.
struct SpeakerDirectory: @unchecked Sendable {
    var defaults: UserDefaults = .standard
    var key: String = AppDefaults.speakersKey

    /// Speakers sorted by mDNS name; empty when nothing has been scanned yet.
    func load() -> [Speaker] {
        let entries = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return entries.map { Speaker(id: $0.key, address: $0.value) }.sorted { $0.id < $1.id }
    }

    /// Stores a scan result. An empty result keeps the existing list (the speakers may just be off).
    func store(_ speakers: [Speaker]) {
        guard !speakers.isEmpty else { return }
        defaults.set(Dictionary(speakers.map { ($0.id, $0.address) }) { _, last in last }, forKey: key)
    }
}
