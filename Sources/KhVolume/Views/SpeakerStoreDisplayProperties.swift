/// View-layer display helpers for SpeakerStore.
/// These computed properties are pure derivations from store state used
/// exclusively for rendering — they belong here rather than in the service.
extension SpeakerStore {

    /// Formatted level label shared by HUD and popover; a dash when muted or when no level is known.
    func volumeLevelText(for level: Double) -> String {
        if isMuted || outputs.isEmpty { return "—" }
        return "\(Int(level.rounded()))"
    }

    var volumeLevelText: String {
        volumeLevelText(for: level)
    }

    /// Normalized slider position (0...1) shared by HUD and popover.
    var volumeFraction: Double {
        guard config.effectiveMax > 0, !isMuted else { return 0 }
        return min(1, max(0, level / config.effectiveMax))
    }

    var isVolumeSliderDisabled: Bool {
        isMuted || isSearching
    }
}
