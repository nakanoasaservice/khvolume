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

@Suite("SpeakerStatusBuilder")
struct SpeakerStatusBuilderTests {

    @Test("combines readings into status")
    func combines() throws {
        let status = try SpeakerStatusBuilder.status(from: [
            ("Left", .init(level: 50, mute: false)),
            ("Right", .init(level: 50.02, mute: true)),
        ])
        #expect(status.levels == [50, 50.02])
        #expect(status.muted)
        #expect(status.balanced)
        #expect(status.devices.keys.sorted() == ["Left", "Right"])
    }

    @Test("levels 0.1 dB apart are unbalanced")
    func unbalanced() throws {
        let status = try SpeakerStatusBuilder.status(from: [
            ("Left", .init(level: 50, mute: false)),
            ("Right", .init(level: 50.1, mute: false)),
        ])
        #expect(!status.balanced)
    }

    @Test("missing level is a device error")
    func missingLevel() {
        #expect(throws: KhvolError.self) {
            try SpeakerStatusBuilder.status(from: [("Left", .init(level: nil, mute: false))])
        }
    }

    @Test("no readings is a device error")
    func empty() {
        #expect(throws: KhvolError.self) {
            try SpeakerStatusBuilder.status(from: [])
        }
    }
}

@Suite("SpeakerDirectory — UserDefaults")
struct SpeakerDirectoryTests {

    @Test("loads addresses sorted by mDNS name")
    func loadsSorted() {
        let directory = SpeakerDirectory(defaults: .makeForTesting())
        directory.store(["Right-2": "fe80::2", "Left-1": "fe80::1"])
        #expect(directory.load() == ["fe80::1", "fe80::2"])
    }

    @Test("empty scan keeps an existing list")
    func emptyScanKeepsList() {
        let directory = SpeakerDirectory(defaults: .makeForTesting())
        directory.store(["Left-1": "fe80::1"])
        directory.store([:])
        #expect(directory.load() == ["fe80::1"])
    }

    @Test("nothing scanned yet loads an empty list")
    func emptyByDefault() {
        #expect(SpeakerDirectory(defaults: .makeForTesting()).load().isEmpty)
    }
}

@Suite("KhvolClient — configuration errors")
struct KhvolClientConfigurationTests {

    @Test("missing interface fails before reading the speaker list")
    func missingInterface() async {
        let client = KhvolClient(interface: nil, speakers: SpeakerDirectory(defaults: .makeForTesting()), pool: SSCSpeakerPool())
        await #expect {
            _ = try await client.jsonStatus()
        } throws: { error in
            (error as? KhvolError)?.errorDescription == "network interface not configured"
        }
    }

    @Test("missing speaker list asks for a scan")
    func missingSpeakerList() async {
        let client = KhvolClient(interface: "en0", speakers: SpeakerDirectory(defaults: .makeForTesting()), pool: SSCSpeakerPool())
        await #expect {
            _ = try await client.jsonStatus()
        } throws: { error in
            guard case .deviceError(let message) = error as? KhvolError else { return false }
            return message == "no speakers configured; run scan"
        }
    }
}
