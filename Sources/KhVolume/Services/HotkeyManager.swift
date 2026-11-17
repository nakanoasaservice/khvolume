import AppKit
import KeyboardShortcuts
import Foundation

extension KeyboardShortcuts.Name {
    static let volumeUp = Self("volumeUp", initial: .init(.equal, modifiers: [.option]))
    static let volumeDown = Self("volumeDown", initial: .init(.minus, modifiers: [.option]))
    static let muteToggle = Self("muteToggle", initial: .init(.m, modifiers: [.control, .option]))
}

@MainActor
final class HotkeyManager {
    private weak var store: (any VolumeAdjustable)?
    private let volumeInteraction: HotkeyVolumeInteraction
    private let volumeHUD = VolumeHUDController()

    init(store: SpeakerStore) {
        self.store = store
        volumeHUD.configure(store: store)
        volumeInteraction = HotkeyVolumeInteraction(store: store, hud: volumeHUD)
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .volumeUp) { [weak self] in
            self?.volumeInteraction.keyDown(.up)
        }
        KeyboardShortcuts.onKeyUp(for: .volumeUp) { [weak self] in
            self?.volumeInteraction.keyUp(.up)
        }

        KeyboardShortcuts.onKeyDown(for: .volumeDown) { [weak self] in
            self?.volumeInteraction.keyDown(.down)
        }
        KeyboardShortcuts.onKeyUp(for: .volumeDown) { [weak self] in
            self?.volumeInteraction.keyUp(.down)
        }

        KeyboardShortcuts.onKeyUp(for: .muteToggle) { [weak self] in
            Task { @MainActor in
                guard let self, let store = self.store else { return }
                await store.toggleMute()
                self.volumeHUD.present()
            }
        }
    }
}
