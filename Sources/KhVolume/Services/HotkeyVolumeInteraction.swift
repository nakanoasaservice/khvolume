import Foundation

/// Handles volume hotkey tap, burst, and hold-to-repeat.
@MainActor
final class HotkeyVolumeInteraction {
    enum Direction: Equatable {
        case up
        case down
    }

    private let store: SpeakerStore
    /// Delay before hold-to-repeat; release within this window counts as a single step.
    private let holdThreshold: Duration
    /// Repeat interval while held.
    private let repeatInterval: Duration
    /// Called after every step, to show the HUD.
    private let onStep: () -> Void
    private var activeDirection: Direction?
    private var repeatTask: Task<Void, Never>?

    init(
        store: SpeakerStore,
        holdThreshold: Duration = .milliseconds(350),
        repeatInterval: Duration = .milliseconds(90),
        onStep: @escaping () -> Void
    ) {
        self.store = store
        self.holdThreshold = holdThreshold
        self.repeatInterval = repeatInterval
        self.onStep = onStep
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
        let step = store.config.levelStep
        switch direction {
        case .up:
            store.adjustLevel(by: step)
        case .down:
            store.adjustLevel(by: -step)
        }
        onStep()
    }

    private func startRepeatIfStillHeld() {
        repeatTask?.cancel()
        guard let heldDirection = activeDirection else { return }
        repeatTask = Task { @MainActor [weak self, holdThreshold, repeatInterval] in
            try? await Task.sleep(for: holdThreshold)
            while !Task.isCancelled, self?.activeDirection == heldDirection {
                self?.applyStep(heldDirection)
                try? await Task.sleep(for: repeatInterval)
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
