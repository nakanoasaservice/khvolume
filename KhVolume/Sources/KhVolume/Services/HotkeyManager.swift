import AppKit
import KeyboardShortcuts
import Foundation

extension KeyboardShortcuts.Name {
    static let volumeUp = Self("volumeUp", default: .init(.equal, modifiers: [.option]))
    static let volumeDown = Self("volumeDown", default: .init(.minus, modifiers: [.option]))
    static let muteToggle = Self("muteToggle", default: .init(.m, modifiers: [.control, .option]))
}

@MainActor
final class HotkeyManager {
    private weak var store: SpeakerStore?
    private let volumeInteraction: HotkeyVolumeInteraction

    init(store: SpeakerStore) {
        self.store = store
        self.volumeInteraction = HotkeyVolumeInteraction(store: store)
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
                await self?.store?.toggleMute()
            }
        }
    }
}
