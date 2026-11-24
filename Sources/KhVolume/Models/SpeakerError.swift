import Foundation

enum SpeakerError: LocalizedError, Equatable {
    case noInterface
    case noSpeakersFound(interface: String)
    case unreachable(speaker: String)
    /// The speaker answered with an SSC error.
    case rejected(speaker: String, reply: String)
    case unexpectedReply(speaker: String)

    var errorDescription: String? {
        switch self {
        case .noInterface: "No network interface selected"
        case .noSpeakersFound(let interface): "No speakers found on \(interface)"
        case .unreachable(let speaker): "\(speaker) is not responding"
        case .rejected(let speaker, let reply): "\(speaker): \(reply)"
        case .unexpectedReply(let speaker): "\(speaker): unexpected reply"
        }
    }
}
