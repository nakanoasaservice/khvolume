import Foundation

/// The scanned speaker list in UserDefaults: `{"<mDNS name>": "<IPv6 address>", …}`.
struct SpeakerDirectory {
    var defaults: UserDefaults = .standard
    var key: String = AppDefaults.speakersKey

    /// Speaker addresses sorted by mDNS name; empty when nothing has been scanned yet.
    func load() -> [String] {
        let entries = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return entries.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Stores a scan result. An empty result keeps the existing list (the speakers may just be off).
    func store(_ found: [String: String]) {
        guard !found.isEmpty else { return }
        defaults.set(found, forKey: key)
    }
}
