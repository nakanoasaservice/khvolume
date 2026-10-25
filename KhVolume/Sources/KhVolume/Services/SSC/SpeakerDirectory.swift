import Foundation

/// The scanned speaker list in `khtool.json`: `{"<mDNS name>": "<IPv6 address>", …}`.
/// Same format khtool/pyssc wrote, so existing installs keep working without a rescan.
struct SpeakerDirectory {
    let url: URL

    /// Speaker addresses sorted by mDNS name; empty when the file is missing or unreadable.
    func load() -> [String] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [] }
        return entries.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Stores a scan result. An empty result keeps an existing non-empty list (the speakers may just
    /// be off) and otherwise removes the file so the next status read asks for a scan.
    func store(_ found: [String: String]) throws {
        if found.isEmpty {
            if load().isEmpty { try? FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(found).write(to: url, options: .atomic)
    }
}
