import Testing
@testable import KhVolume

@Suite("SpeakerStore — apply(json:) mapping")
@MainActor
struct SpeakerStoreJSONMappingTests {

    @Test("apply sorts devices alphabetically")
    func devicesAreSorted() {
        let store = SpeakerStore.makeForTesting()
        let json = KhvolJSONStatus.stub(
            devices: [
                "zeta": .init(level: 40, mute: false),
                "alpha": .init(level: 80, mute: false),
                "mu": .init(level: 60, mute: false),
            ],
            levels: [40, 80, 60]
        )
        store.apply(json: json)
        let names = store.status.devices.map(\.name)
        #expect(names == ["alpha", "mu", "zeta"])
    }

    @Test("apply computes averageLevel as mean of levels")
    func averageLevelMean() {
        let store = SpeakerStore.makeForTesting()
        let json = KhvolJSONStatus.stub(levels: [60, 80])
        store.apply(json: json)
        #expect(store.status.averageLevel == 70)
    }

    @Test("apply sets averageLevel to 0 when levels array is empty")
    func averageLevelEmptyLevels() {
        let store = SpeakerStore.makeForTesting()
        let json = KhvolJSONStatus.stub(levels: [])
        store.apply(json: json)
        #expect(store.status.averageLevel == 0)
    }

    @Test("apply reflects isMuted from JSON")
    func isMutedReflected() {
        let store = SpeakerStore.makeForTesting()
        store.apply(json: .stub(muted: true))
        #expect(store.status.isMuted == true)

        store.apply(json: .stub(muted: false))
        #expect(store.status.isMuted == false)
    }

    @Test("apply sets levelMismatch = !balanced")
    func levelMismatchFromBalanced() {
        let store = SpeakerStore.makeForTesting()
        store.apply(json: .stub(balanced: false))
        #expect(store.status.levelMismatch == true)

        store.apply(json: .stub(balanced: true))
        #expect(store.status.levelMismatch == false)
    }

    @Test("apply maps device level and mute correctly")
    func deviceLevelMapped() {
        let store = SpeakerStore.makeForTesting()
        let json = KhvolJSONStatus.stub(
            devices: ["speaker": .init(level: 77, mute: true)],
            levels: [77]
        )
        store.apply(json: json)
        let device = store.status.devices.first
        #expect(device?.level == 77)
        #expect(device?.muted == true)
    }

    @Test("apply treats nil device level as 0")
    func nilDeviceLevelDefaultsToZero() {
        let store = SpeakerStore.makeForTesting()
        let json = KhvolJSONStatus.stub(
            devices: ["speaker": .init(level: nil, mute: nil)],
            levels: [0]
        )
        store.apply(json: json)
        #expect(store.status.devices.first?.level == 0)
        #expect(store.status.devices.first?.muted == false)
    }
}
