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

    @Test("messages for a KH 750's own output name out5")
    func out5Messages() {
        #expect(SSCMessage.outputQuery() == #"{"audio":{"out":{"level":null,"mute":null}}}"#)
        #expect(SSCMessage.outputQuery(.out5) == #"{"audio":{"out5":{"level":null,"mute":null}}}"#)
        #expect(SSCMessage.setLevel(49, node: .out5) == #"{"audio":{"out5":{"level":49.0}}}"#)
        #expect(SSCMessage.setMuted(true, node: .out5) == #"{"audio":{"out5":{"mute":true}}}"#)
    }

    @Test("the output node follows khtool's rule", arguments: [
        ("KH 80", "1_3_1", SSCMessage.OutputNode.out),
        ("KH 120 II", "1_2_0", .out),
        ("KH 750", "1_0_5", .out),
        ("KH 750", "1_1_2", .out),
        ("KH 750", "1_2_4", .out5),
        ("KH 750", "1_5_0", .out5),
        ("KH 750", "2_0_3", .out),
        ("KH 750", nil, .out5),
        (nil, nil, .out),
    ] as [(String?, String?, SSCMessage.OutputNode)])
    func outputNode(product: String?, version: String?, expected: SSCMessage.OutputNode) {
        #expect(SSCMessage.OutputNode(product: product, version: version) == expected)
    }

    @Test("parses product and version, and an output at out5")
    func parseIdentityAndOut5() {
        #expect(SSCMessage.parseProduct(#"{"device":{"identity":{"product":"KH 750"}}}"#) == "KH 750")
        #expect(SSCMessage.parseVersion(#"{"device":{"identity":{"version":"1_2_4"}}}"#) == "1_2_4")
        #expect(SSCMessage.parseProduct(#"{"osc":{"error":[404,{"desc":"address not found"}]}}"#) == nil)

        let reply = #"{"audio":{"out5":{"level":52.0,"mute":true}}}"#
        #expect(SSCMessage.parseOutput(reply, node: .out5) == SSCMessage.Output(level: 52, mute: true))
        #expect(SSCMessage.parseOutput(reply) == nil)
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
