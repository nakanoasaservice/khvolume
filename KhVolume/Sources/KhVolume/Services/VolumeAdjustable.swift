import Foundation

/// The volume-control interface used by HotkeyVolumeInteraction and HotkeyManager,
/// so they do not need a direct reference to the concrete SpeakerStore.
@MainActor
protocol VolumeAdjustable: AnyObject {
    var config: AppConfig { get }
    func adjustVolume(by delta: Double)
    func setVolumePreview(_ level: Double)
    func toggleMute() async
}

extension SpeakerStore: VolumeAdjustable {}
