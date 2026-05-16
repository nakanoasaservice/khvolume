import Foundation

struct AppConfig: Codable, Equatable {
    var networkInterface: String?

    enum CodingKeys: String, CodingKey {
        case networkInterface = "interface"
        case maxVolumeLimit
        case volumeStep
        case launchAtLogin
        case allowForceOnMismatch
        case hotkeyVolumeUp
        case hotkeyVolumeDown
        case hotkeyMuteToggle
    }
    var maxVolumeLimit: Double = 120
    var volumeStep: Double = 1
    var launchAtLogin: Bool = false
    var allowForceOnMismatch: Bool = false

    var hotkeyVolumeUp: String = "option+equal"
    var hotkeyVolumeDown: String = "option+minus"
    var hotkeyMuteToggle: String = "control+option+m"

    var effectiveMax: Double {
        min(120, max(0, maxVolumeLimit))
    }
}
