import Foundation
import Testing
@testable import KhVolume

@Suite("SSCMessage — building and parsing")
struct SSCMessageTests {

    @Test("set messages match what khtool sent")
    func setMessages() {
        #expect(SSCMessage.setLevel(49) == #"{"audio":{"out":{"level":49.0}}}"#)
        #expect(SSCMessage.setLevel(49.26) == #"{"audio":{"out":{"level":49.3}}}"#)
        #expect(SSCMessage.setMuted(true) == #"{"audio":{"out":{"mute":true}}}"#)
        #expect(SSCMessage.setMuted(false) == #"{"audio":{"out":{"mute":false}}}"#)
    }

    @Test("parses device name and output replies")
    func parseReplies() {
        #expect(SSCMessage.parseDeviceName(#"{"device":{"name":"Left"}}"#) == "Left")
        let output = SSCMessage.parseOutput(#"{"audio":{"out":{"level":52.0,"mute":false}}}"#)
        #expect(output?.level == 52.0)
        #expect(output?.mute == false)
        #expect(SSCMessage.parseOutput("garbage") == nil)
    }

    @Test("detects OSC error replies")
    func errorReplies() {
        #expect(SSCMessage.isError(#"{"osc":{"error":[400,{"desc":"message not understood"}]}}"#))
        #expect(!SSCMessage.isError(#"{"audio":{"out":{"mute":true}}}"#))
    }
}

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
        let stored = defaults.dictionary(forKey: AppDefaults.speakersKey) as? [String: String]
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
