import Testing
@testable import KhVolume

@Suite("SpeakerStore — JSON mapping")
@MainActor
struct SpeakerStoreJSONMappingTests {

    @Test("sorts devices alphabetically")
    func devicesAreSorted() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(KhvolJSONStatus.stub(
            devices: [
                "zeta": .init(level: 40, mute: false),
                "alpha": .init(level: 80, mute: false),
                "mu": .init(level: 60, mute: false),
            ],
            levels: [40, 80, 60]
        ))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        let names = store.status.devices.map(\.name)
        #expect(names == ["alpha", "mu", "zeta"])
    }

    @Test("computes averageLevel as mean of levels")
    func averageLevelMean() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(levels: [60, 80]))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.averageLevel == 70)
    }

    @Test("sets averageLevel to 0 when levels array is empty")
    func averageLevelEmptyLevels() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(levels: []))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.averageLevel == 0)
    }

    @Test("reflects isMuted from JSON")
    func isMutedReflected() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)

        mock.jsonStatusResult = .success(.stub(muted: true))
        await store.refresh()
        #expect(store.status.isMuted == true)

        mock.jsonStatusResult = .success(.stub(muted: false))
        await store.refresh()
        #expect(store.status.isMuted == false)
    }

    @Test("sets levelMismatch = !balanced")
    func levelMismatchFromBalanced() async {
        let mock = MockKhvolClient()
        let store = SpeakerStore.makeForTesting(client: mock)

        mock.jsonStatusResult = .success(.stub(balanced: false))
        await store.refresh()
        #expect(store.status.levelMismatch == true)

        mock.jsonStatusResult = .success(.stub(balanced: true))
        await store.refresh()
        #expect(store.status.levelMismatch == false)
    }

    @Test("maps device level and mute correctly")
    func deviceLevelMapped() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(
            devices: ["speaker": .init(level: 77, mute: true)],
            levels: [77]
        ))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        let device = store.status.devices.first
        #expect(device?.level == 77)
        #expect(device?.muted == true)
    }

    @Test("treats nil device level as 0")
    func nilDeviceLevelDefaultsToZero() async {
        let mock = MockKhvolClient()
        mock.jsonStatusResult = .success(.stub(
            devices: ["speaker": .init(level: nil, mute: nil)],
            levels: [0]
        ))
        let store = SpeakerStore.makeForTesting(client: mock)

        await store.refresh()

        #expect(store.status.devices.first?.level == 0)
        #expect(store.status.devices.first?.muted == false)
    }
}
