import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case ready
    case warning
}

struct DeviceLevel: Identifiable, Equatable {
    let id: String
    let name: String
    let level: Double
    let muted: Bool
}

struct SpeakerStatus: Equatable {
    var devices: [DeviceLevel] = []
    var averageLevel: Double = 0
    var isMuted: Bool = false
    var levelMismatch: Bool = false
    var lastError: String?
}

struct NetworkInterfaceInfo: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let label: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case name, label, status
    }

    init(name: String, label: String, status: String) {
        self.id = name
        self.name = name
        self.label = label
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decode(String.self, forKey: .label)
        status = try c.decode(String.self, forKey: .status)
        id = name
    }
}
struct KhvolJSONStatus: Codable {
    struct DeviceInfo: Codable {
        let level: Double?
        let mute: Bool?
    }

    let devices: [String: DeviceInfo]
    let levels: [Double]
    let muted: Bool
    let balanced: Bool
}
