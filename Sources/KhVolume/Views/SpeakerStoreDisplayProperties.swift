/// View-layer display helpers for SpeakerStore.
/// These computed properties are pure derivations from store state used
/// exclusively for rendering — they belong here rather than in the service.
extension SpeakerStore {

    /// Formatted level label shared by HUD and popover; a dash when muted or when no level is known.
    func levelText(for level: Double) -> String {
        if isMuted || outputs.isEmpty { return "—" }
        return "\(Int(level.rounded()))"
    }

    var levelText: String {
        levelText(for: level)
    }

    /// Normalized slider position (0...1) shared by HUD and popover.
    var levelFraction: Double {
        guard config.maxLevel > 0, !isMuted else { return 0 }
        return (level / config.maxLevel).clamped(to: 0...1)
    }

    /// The speakers being controlled, so that a missing or an unexpected one can be seen.
    var speakerNamesText: String {
        outputs.map(\.name).sorted().joined(separator: ", ")
    }

    var isVolumeSliderDisabled: Bool {
        isMuted || isSearching
    }
}
