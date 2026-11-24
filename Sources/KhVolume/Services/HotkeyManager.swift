import AppKit
import KeyboardShortcuts
import Foundation

extension KeyboardShortcuts.Name {
    static let volumeUp = Self("volumeUp", initial: .init(.equal, modifiers: [.option]))
    static let volumeDown = Self("volumeDown", initial: .init(.minus, modifiers: [.option]))
    static let muteToggle = Self("muteToggle", initial: .init(.m, modifiers: [.control, .option]))
}

/// The global hotkeys: an input to the store, like the views, with the HUD as their feedback.
@MainActor
final class HotkeyManager {
    private let store: SpeakerStore
    private let volumeInteraction: HotkeyVolumeInteraction
    private let volumeHUD: VolumeHUDController

    init(store: SpeakerStore) {
        let volumeHUD = VolumeHUDController(store: store)
        self.store = store
        self.volumeHUD = volumeHUD
        volumeInteraction = HotkeyVolumeInteraction(store: store) { volumeHUD.present() }
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
                guard let self else { return }
                await self.store.toggleMute()
                self.volumeHUD.present()
            }
        }
    }
}
