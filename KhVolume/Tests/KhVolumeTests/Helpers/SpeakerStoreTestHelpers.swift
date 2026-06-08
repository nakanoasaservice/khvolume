@testable import KhVolume

extension SpeakerStore {
    static func makeForTesting(
        config: AppConfig = AppConfig(),
        client: MockKhvolClient = MockKhvolClient()
    ) -> SpeakerStore {
        SpeakerStore(config: config, clientFactory: { client })
    }
}
