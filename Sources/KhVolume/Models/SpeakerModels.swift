import Foundation

/// A speaker found on the network.
struct Speaker: Hashable, Sendable {
    /// mDNS service name; unique on the network, unlike the SSC device name.
    let id: String
    /// IPv6 address without the interface scope.
    let address: String
}

/// What one speaker last reported about its output.
struct SpeakerOutput: Identifiable, Equatable, Sendable {
    /// The speaker's mDNS service name.
    let id: String
    /// SSC device name ("Left", "Right"…); two speakers may share one.
    var name: String
    var level: Double
    var muted: Bool
}

extension Collection where Element == SpeakerOutput {
    /// Levels closer than this count as the same level.
    static var balanceTolerance: Double { 0.05 }

    /// True when every speaker is at the same level.
    var isBalanced: Bool {
        guard let lowest = map(\.level).min(), let highest = map(\.level).max() else { return true }
        return highest - lowest < Self.balanceTolerance
    }

    var isMuted: Bool {
        contains(where: \.muted)
    }

    /// The level of the group: the quietest speaker's, so that a level at or below it never makes
    /// any speaker louder. 0 when no speaker has reported.
    var level: Double {
        map(\.level).min() ?? 0
    }
}

enum ConnectionState: Equatable {
    /// Nothing has been read from the speakers yet.
    case disconnected
    /// Looking for speakers; this takes seconds, so controls are disabled meanwhile.
    case searching
    case connected
    case failed(SpeakerError)
}

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

struct NetworkInterfaceInfo: Identifiable, Equatable {
    let name: String
    let label: String
    /// Whether the port has link.
    let isActive: Bool

    var id: String { name }
}
