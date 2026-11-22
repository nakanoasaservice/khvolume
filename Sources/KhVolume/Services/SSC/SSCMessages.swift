import Foundation

/// SSC (Sennheiser Sound Control) messages used by KH Volume, and parsing of their replies.
enum SSCMessage {
    /// The `audio.out` part of a reply; a speaker only includes the values that were asked for or set.
    struct Output: Equatable {
        let level: Double?
        let mute: Bool?
    }

    static let deviceNameQuery = #"{"device":{"name":null}}"#
    static let outputQuery = #"{"audio":{"out":{"level":null,"mute":null}}}"#

    static func setLevel(_ level: Double) -> String {
        #"{"audio":{"out":{"level":\#(String(format: "%.1f", level))}}}"#
    }

    static func setMuted(_ muted: Bool) -> String {
        #"{"audio":{"out":{"mute":\#(muted)}}}"#
    }

    /// `{"device":{"name":"Left"}}` → "Left"
    static func parseDeviceName(_ reply: String) -> String? {
        (object(reply)?["device"] as? [String: Any])?["name"] as? String
    }

    /// `{"audio":{"out":{"level":52.0,"mute":false}}}` → level and mute (either may be missing).
    static func parseOutput(_ reply: String) -> Output? {
        guard let audio = object(reply)?["audio"] as? [String: Any],
              let out = audio["out"] as? [String: Any]
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

    private static func object(_ reply: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]
    }
}
