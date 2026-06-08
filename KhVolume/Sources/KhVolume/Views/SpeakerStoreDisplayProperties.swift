/// View-layer display helpers for SpeakerStore.
/// These computed properties are pure derivations from store state used
/// exclusively for rendering — they belong here rather than in the service.
extension SpeakerStore {

    /// Formatted level label shared by HUD and popover.
    func volumeLevelText(for level: Double) -> String {
        if status.isMuted { return "—" }
        return "\(Int(level.rounded()))"
    }

    var volumeLevelText: String {
        volumeLevelText(for: previewAverageLevel)
    }

    /// Normalized slider position (0...1) shared by HUD and popover.
    var volumeFraction: Double {
        guard config.effectiveMax > 0, !status.isMuted else { return 0 }
        return min(1, max(0, previewAverageLevel / config.effectiveMax))
    }

    var isVolumeSliderDisabled: Bool {
        status.isMuted || isStatusLoading
    }
}
