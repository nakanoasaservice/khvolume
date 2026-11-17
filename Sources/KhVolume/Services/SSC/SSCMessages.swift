import Foundation

/// SSC (Sennheiser Sound Control) messages used by KH Volume, and parsing of their replies.
enum SSCMessage {
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
    static func parseOutput(_ reply: String) -> KhvolJSONStatus.DeviceInfo? {
        guard let audio = object(reply)?["audio"] as? [String: Any],
              let out = audio["out"] as? [String: Any]
        else { return nil }
        return KhvolJSONStatus.DeviceInfo(
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

enum SpeakerStatusBuilder {
    /// Levels closer than this count as balanced.
    static let balanceTolerance = 0.05

    /// Combines per-speaker readings (in speaker order) into the status the store consumes.
    static func status(from readings: [(name: String, output: KhvolJSONStatus.DeviceInfo)]) throws(KhvolError) -> KhvolJSONStatus {
        guard !readings.isEmpty else { throw .deviceError("no devices found") }
        let levels = readings.compactMap(\.output.level)
        guard levels.count == readings.count else {
            throw .deviceError("missing level from one or more devices")
        }
        var devices: [String: KhvolJSONStatus.DeviceInfo] = [:]
        for reading in readings { devices[reading.name] = reading.output }
        return KhvolJSONStatus(
            devices: devices,
            levels: levels,
            muted: readings.contains { $0.output.mute == true },
            balanced: levels.max()! - levels.min()! < balanceTolerance
        )
    }
}
