import Foundation

struct AppConfig: Codable, Equatable {
    var networkInterface: String?

    enum CodingKeys: String, CodingKey {
        case networkInterface = "interface"
        case maxVolumeLimit
        case volumeStep
        case allowForceOnMismatch
    }
    var maxVolumeLimit: Double = SpeakerGroup.maxLevel
    var volumeStep: Double = 1
    var allowForceOnMismatch: Bool = false

    var effectiveMax: Double {
        min(SpeakerGroup.maxLevel, max(0, maxVolumeLimit))
    }
}
