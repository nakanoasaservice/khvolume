import Foundation

/// Handles volume hotkey tap, burst, and hold-to-repeat.
@MainActor
final class HotkeyVolumeInteraction {
    enum Direction: Equatable {
        case up
        case down
    }

    private weak var store: SpeakerStore?
    private var activeDirection: Direction?
    private var repeatTask: Task<Void, Never>?

    /// Delay before hold-to-repeat; release within this window counts as a single step.
    private let holdThresholdNanos: UInt64 = 350_000_000
    /// Repeat interval while held.
    private let repeatIntervalNanos: UInt64 = 90_000_000

    init(store: SpeakerStore) {
        self.store = store
    }

    func keyDown(_ direction: Direction) {
        if activeDirection == direction {
            return
        }
        stopRepeat()
        activeDirection = direction
        applyStep(direction)
        startRepeatIfStillHeld()
    }

    func keyUp(_ direction: Direction) {
        guard activeDirection == direction else { return }
        activeDirection = nil
        stopRepeat()
    }

    private func applyStep(_ direction: Direction) {
        guard let store else { return }
        let step = store.config.volumeStep
        switch direction {
        case .up:
            store.adjustLevelByHotkey(delta: step)
        case .down:
            store.adjustLevelByHotkey(delta: -step)
        }
    }

    private func startRepeatIfStillHeld() {
        repeatTask?.cancel()
        guard let heldDirection = activeDirection else { return }
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.holdThresholdNanos ?? 350_000_000)
            while !Task.isCancelled, self?.activeDirection == heldDirection {
                self?.applyStep(heldDirection)
                try? await Task.sleep(nanoseconds: self?.repeatIntervalNanos ?? 90_000_000)
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
