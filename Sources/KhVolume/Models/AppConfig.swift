import Foundation

/// The user's settings. The keys are the names the settings were first stored under, so that a
/// stored config still decodes after a property is renamed.
struct AppConfig: Codable, Equatable {
    var networkInterface: String?
    /// The highest level the user lets the app set.
    var levelLimit: Double = SpeakerOutput.levelRange.upperBound
    /// How far one hotkey press moves the level.
    var levelStep: Double = 1
    var allowsIncreaseWhileUnbalanced: Bool = false

    enum CodingKeys: String, CodingKey {
        case networkInterface = "interface"
        case levelLimit = "maxVolumeLimit"
        case levelStep = "volumeStep"
        case allowsIncreaseWhileUnbalanced = "allowForceOnMismatch"
    }

    /// `levelLimit`, kept within what a speaker accepts.
    var maxLevel: Double {
        levelLimit.clamped(to: SpeakerOutput.levelRange)
    }
}
