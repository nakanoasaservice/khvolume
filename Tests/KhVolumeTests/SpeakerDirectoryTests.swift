import Foundation
import Testing
@testable import KhVolume

@Suite("SpeakerDirectory — UserDefaults")
struct SpeakerDirectoryTests {

    private let left = Speaker(id: "Left-1", address: "fe80::1")
    private let right = Speaker(id: "Right-2", address: "fe80::2")

    @Test("loads speakers sorted by mDNS name")
    func loadsSorted() {
        let directory = SpeakerDirectory(defaults: .makeForTesting())
        directory.store([right, left])
        #expect(directory.load() == [left, right])
    }

    @Test("stores a plain name-to-address dictionary")
    func storedFormat() {
        let defaults = UserDefaults.makeForTesting()
        SpeakerDirectory(defaults: defaults).store([left, right])
        let stored = defaults.dictionary(forKey: SpeakerDirectory.key) as? [String: String]
        #expect(stored == ["Left-1": "fe80::1", "Right-2": "fe80::2"])
    }

    @Test("empty scan keeps an existing list")
    func emptyScanKeepsList() {
        let directory = SpeakerDirectory(defaults: .makeForTesting())
        directory.store([left])
        directory.store([])
        #expect(directory.load() == [left])
    }

    @Test("nothing scanned yet loads an empty list")
    func emptyByDefault() {
        #expect(SpeakerDirectory(defaults: .makeForTesting()).load().isEmpty)
    }
}
