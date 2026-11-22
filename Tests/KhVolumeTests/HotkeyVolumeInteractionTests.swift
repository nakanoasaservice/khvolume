import Testing
@testable import KhVolume

/// These tests wait in real time: the hold and repeat delays are what is being tested.
@Suite("HotkeyVolumeInteraction — tap and hold")
@MainActor
struct HotkeyVolumeInteractionTests {
    private func makeKeys(onStep: @escaping () -> Void) -> (HotkeyVolumeInteraction, SpeakerStore) {
        let store = SpeakerStore.makeForTesting(outputs: [.stub(level: 50)])
        let keys = HotkeyVolumeInteraction(
            store: store, holdThreshold: .milliseconds(40), repeatInterval: .milliseconds(5), onStep: onStep
        )
        return (keys, store)
    }

    @Test("a tap is one step")
    func tap() async throws {
        var steps = 0
        let (keys, store) = makeKeys { steps += 1 }

        keys.keyDown(.down)
        keys.keyUp(.down)
        try await Task.sleep(for: .milliseconds(100))

        #expect(steps == 1)
        #expect(store.level == 49)
    }

    @Test("holding repeats the step, and releasing stops it")
    func holdRepeatsUntilRelease() async throws {
        var steps = 0
        // The keys hold the store weakly, so it has to be kept here.
        let (keys, store) = makeKeys { steps += 1 }

        keys.keyDown(.up)
        #expect(steps == 1)
        try await Task.sleep(for: .milliseconds(200))
        keys.keyUp(.up)

        let stepsWhileHeld = steps
        #expect(stepsWhileHeld > 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(steps == stepsWhileHeld)
        #expect(store.level == 50 + Double(stepsWhileHeld))
    }
}
