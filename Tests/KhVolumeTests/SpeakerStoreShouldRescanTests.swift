import Testing
@testable import KhVolume

@Suite("SpeakerStore — shouldRescan(after:)")
@MainActor
struct SpeakerStoreShouldRescanTests {

    // MARK: Message-based triggers (cache present)

    @Test("returns true for message containing 'run scan' (case insensitive)", arguments: [
        "please run scan now",
        "RUN SCAN REQUIRED",
        "Run Scan",
        "you must run scan",
    ])
    func runScanMessageTriggersRescan(message: String) {
        let store = SpeakerStore.makeForTesting()  // hasSpeakerCache = { true }
        #expect(store.shouldRescan(after: message) == true)
    }

    @Test("returns true for message containing 'no speakers configured'", arguments: [
        "error: no speakers configured",
        "No Speakers Configured",
        "NO SPEAKERS CONFIGURED",
    ])
    func noSpeakersMessageTriggersRescan(message: String) {
        let store = SpeakerStore.makeForTesting()  // hasSpeakerCache = { true }
        #expect(store.shouldRescan(after: message) == true)
    }

    @Test("returns false for unrelated message when cache exists")
    func unrelatedMessageNoRescan() {
        let store = SpeakerStore.makeForTesting()  // hasSpeakerCache = { true }
        #expect(store.shouldRescan(after: "connection timed out") == false)
        #expect(store.shouldRescan(after: "device busy") == false)
        #expect(store.shouldRescan(after: "") == false)
    }

    // MARK: Cache-absent short-circuit

    @Test("returns true for any message when no speaker cache")
    func noCacheAlwaysRescan() {
        let store = SpeakerStore.makeForTesting(hasSpeakerCache: { false })
        // Even a completely unrelated message triggers a rescan when the cache is absent
        #expect(store.shouldRescan(after: "connection timed out") == true)
        #expect(store.shouldRescan(after: "") == true)
    }

    @Test("returns true for matching message regardless of cache state", arguments: [true, false])
    func matchingMessageAlwaysRescan(cacheExists: Bool) {
        let store = SpeakerStore.makeForTesting(hasSpeakerCache: { cacheExists })
        #expect(store.shouldRescan(after: "please run scan now") == true)
    }
}
