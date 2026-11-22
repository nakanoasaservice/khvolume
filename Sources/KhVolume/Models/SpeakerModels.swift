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

struct NetworkInterfaceInfo: Identifiable, Equatable {
    let name: String
    let label: String
    let status: String

    var id: String { name }
}

struct KhvolJSONStatus {
    struct DeviceInfo {
        let level: Double?
        let mute: Bool?
    }

    let devices: [String: DeviceInfo]
    let levels: [Double]
    let muted: Bool
    let balanced: Bool
}
