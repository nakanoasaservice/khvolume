import Foundation

/// SSC (Sennheiser Sound Control) messages used by KH Volume, and parsing of their replies.
enum SSCMessage {
    /// The node under `audio` that holds the level and mute of a device's own output.
    enum OutputNode: String, Sendable {
        case out
        /// The subwoofer itself on a KH 750 whose firmware has `out1`…`out4` for the monitors
        /// connected to it.
        case out5

        static let kh750 = "KH 750"

        /// Only a KH 750 has more than one output, and where its own is depends on the firmware:
        /// `out` up to 1.1 and from 2.0, `out5` in between. This is khtool's rule.
        init(product: String?, version: String?) {
            let usesOut = ["1_0", "1_1", "2_"].contains { version?.hasPrefix($0) ?? false }
            self = product == Self.kh750 && !usesOut ? .out5 : .out
        }
    }

    /// The output part of a reply; a speaker only includes the values that were asked for or set.
    struct Output: Equatable {
        let level: Double?
        let mute: Bool?
    }

    static let deviceNameQuery = #"{"device":{"name":null}}"#
    static let productQuery = #"{"device":{"identity":{"product":null}}}"#
    static let versionQuery = #"{"device":{"identity":{"version":null}}}"#

    static func outputQuery(_ node: OutputNode = .out) -> String {
        #"{"audio":{"\#(node.rawValue)":{"level":null,"mute":null}}}"#
    }

    static func setLevel(_ level: Double, node: OutputNode = .out) -> String {
        #"{"audio":{"\#(node.rawValue)":{"level":\#(String(format: "%.1f", level))}}}"#
    }

    static func setMuted(_ muted: Bool, node: OutputNode = .out) -> String {
        #"{"audio":{"\#(node.rawValue)":{"mute":\#(muted)}}}"#
    }

    /// `{"device":{"name":"Left"}}` → "Left"
    static func parseDeviceName(_ reply: String) -> String? {
        (object(reply)?["device"] as? [String: Any])?["name"] as? String
    }

    /// `{"device":{"identity":{"product":"KH 750"}}}` → "KH 750"
    static func parseProduct(_ reply: String) -> String? {
        identity(reply)?["product"] as? String
    }

    /// `{"device":{"identity":{"version":"1_2_4"}}}` → "1_2_4"
    static func parseVersion(_ reply: String) -> String? {
        identity(reply)?["version"] as? String
    }

    /// `{"audio":{"out":{"level":52.0,"mute":false}}}` → level and mute (either may be missing).
    static func parseOutput(_ reply: String, node: OutputNode = .out) -> Output? {
        guard let audio = object(reply)?["audio"] as? [String: Any],
              let out = audio[node.rawValue] as? [String: Any]
        else { return nil }
        return Output(
            level: (out["level"] as? NSNumber)?.doubleValue,
            mute: out["mute"] as? Bool
        )
    }

    /// Devices answer bad requests with `{"osc":{"error":…}}` instead of failing the connection.
    static func isError(_ reply: String) -> Bool {
        (object(reply)?["osc"] as? [String: Any])?["error"] != nil
    }

    private static func identity(_ reply: String) -> [String: Any]? {
        (object(reply)?["device"] as? [String: Any])?["identity"] as? [String: Any]
    }

    private static func object(_ reply: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]
    }
}
