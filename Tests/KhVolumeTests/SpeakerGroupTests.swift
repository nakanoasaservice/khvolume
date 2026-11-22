import Foundation
import os
import Testing
@testable import KhVolume

/// `SpeakerGroup` against a loopback SSC device, with the speaker list in a test UserDefaults suite.
@Suite("SpeakerGroup — connections and requests")
struct SpeakerGroupTests {
    private static let fake = Speaker(id: "fake", address: "::1")
    private static let outputReply = #"{"audio":{"out":{"level":50.0,"mute":false}}}"#

    /// A group that knows the fake speaker from an earlier scan; `scans` counts new scans.
    private func makeGroup(
        _ server: FakeSSCServer,
        stored: [Speaker] = [fake],
        found: [Speaker] = [],
        scans: OSAllocatedUnfairLock<Int> = .init(initialState: 0)
    ) -> (SpeakerGroup, SpeakerDirectory) {
        let directory = SpeakerDirectory(defaults: .makeForTesting())
        directory.store(stored)
        let group = SpeakerGroup(directory: directory, port: server.port, timeout: 1) { _ in
            scans.withLock { $0 += 1 }
            return found
        }
        return (group, directory)
    }

    // MARK: connect

    @Test("connect reads the stored speakers without scanning")
    func connectUsesStoredSpeakers() async throws {
        let server = try FakeSSCServer()
        let scans = OSAllocatedUnfairLock(initialState: 0)
        let (group, _) = makeGroup(server, scans: scans)

        let outputs = try await group.connect(interface: "lo0", rescan: false)

        #expect(outputs == [SpeakerOutput(id: "fake", name: "Fake", level: 50, muted: false)])
        #expect(scans.withLock { $0 } == 0)
    }

    @Test("connect scans and stores the speakers when none are stored")
    func connectScansWithoutStoredSpeakers() async throws {
        let server = try FakeSSCServer()
        let scans = OSAllocatedUnfairLock(initialState: 0)
        let (group, directory) = makeGroup(server, stored: [], found: [Self.fake], scans: scans)

        let outputs = try await group.connect(interface: "lo0", rescan: false)

        #expect(outputs.map(\.id) == ["fake"])
        #expect(scans.withLock { $0 } == 1)
        #expect(directory.load() == [Self.fake])
    }

    @Test("rescan scans even when speakers are stored")
    func rescanIgnoresStoredSpeakers() async throws {
        let server = try FakeSSCServer()
        let scans = OSAllocatedUnfairLock(initialState: 0)
        let (group, _) = makeGroup(server, found: [Self.fake], scans: scans)

        _ = try await group.connect(interface: "lo0", rescan: true)

        #expect(scans.withLock { $0 } == 1)
    }

    @Test("a scan that finds nothing fails and keeps the stored speakers")
    func scanFindsNothing() async throws {
        let server = try FakeSSCServer()
        let (group, directory) = makeGroup(server)

        await #expect(throws: SpeakerError.noSpeakersFound(interface: "lo0")) {
            _ = try await group.connect(interface: "lo0", rescan: true)
        }
        #expect(directory.load() == [Self.fake])
    }

    @Test("connect without an interface fails", arguments: [nil, ""] as [String?])
    func connectWithoutInterface(interface: String?) async throws {
        let (group, _) = makeGroup(try FakeSSCServer())
        await #expect(throws: SpeakerError.noInterface) {
            _ = try await group.connect(interface: interface, rescan: false)
        }
    }

    @Test("requests before a connect fail")
    func requestBeforeConnect() async throws {
        let (group, _) = makeGroup(try FakeSSCServer())
        await #expect(throws: SpeakerError.noInterface) {
            _ = try await group.setLevel(40)
        }
    }

    // MARK: connections

    @Test("reuses one connection per speaker and asks what it is once")
    func reusesConnection() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        for _ in 0..<3 {
            _ = try await group.connect(interface: "lo0", rescan: false)
        }
        #expect(server.acceptedCount == 1)
        #expect(server.requests.filter { $0 == SSCMessage.deviceNameQuery }.count == 1)
        #expect(server.requests.filter { $0 == SSCMessage.productQuery }.count == 1)
        // Only a KH 750 is asked for its firmware.
        #expect(!server.requests.contains(SSCMessage.versionQuery))
    }

    @Test("reconnects once when the reused connection was dropped")
    func reconnectsAfterDrop() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)
        server.dropClients()
        #expect(server.waitUntil { server.openCount == 0 })

        let outputs = try await group.setMuted(true)

        #expect(outputs.map(\.muted) == [true])
        #expect(server.acceptedCount == 2)
    }

    @Test("disconnect releases the speaker's connection; the next request reconnects")
    func disconnectReleases() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)
        #expect(server.openCount == 1)

        await group.disconnect()
        #expect(server.waitUntil { server.openCount == 0 })

        _ = try await group.connect(interface: "lo0", rescan: false)
        #expect(server.acceptedCount == 2)
    }

    @Test("changing the interface replaces existing connections")
    func interfaceChangeReconnects() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)
        _ = try await group.connect(interface: "lo1", rescan: false)
        #expect(server.acceptedCount == 2)
        #expect(server.waitUntil { server.openCount == 1 })
    }

    @Test("a speaker that does not answer is unreachable")
    func unreachable() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        server.stop()
        await #expect(throws: SpeakerError.unreachable(speaker: "::1")) {
            _ = try await group.connect(interface: "lo0", rescan: false)
        }
    }

    // MARK: set

    @Test("setLevel takes the applied level from the reply, without reading again")
    func setLevelUsesReply() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)

        let outputs = try await group.setLevel(42)

        #expect(outputs == [SpeakerOutput(id: "fake", name: "Fake", level: 42, muted: false)])
        #expect(server.requests.filter { $0 == SSCMessage.outputQuery() }.count == 1)
    }

    @Test("setLevel keeps the level within what the speakers accept")
    func setLevelClamps() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)

        _ = try await group.setLevel(500)

        #expect(server.requests.last == SSCMessage.setLevel(120))
    }

    @Test("setMuted takes the applied mute from the reply and keeps the level")
    func setMutedUsesReply() async throws {
        let server = try FakeSSCServer()
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)

        let outputs = try await group.setMuted(true)

        #expect(outputs == [SpeakerOutput(id: "fake", name: "Fake", level: 50, muted: true)])
    }

    @Test("a set reply without the applied value falls back to reading")
    func setFallsBackToReading() async throws {
        let server = try FakeSSCServer { line in
            if line.contains(#""name":null"#) { return #"{"device":{"name":"Fake"}}"# }
            if line.contains(#""level":null"#) { return Self.outputReply }
            return "{}"
        }
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)

        let outputs = try await group.setLevel(42)

        #expect(outputs.map(\.level) == [50])
        #expect(server.requests.filter { $0 == SSCMessage.outputQuery() }.count == 2)
    }

    @Test("an SSC error reply is reported with the speaker's name")
    func rejected() async throws {
        let errorReply = #"{"osc":{"error":[400,{"desc":"message not understood"}]}}"#
        let server = try FakeSSCServer { line in
            if line.contains(#""name":null"#) { return #"{"device":{"name":"Fake"}}"# }
            if line.contains(#""level":null"#) { return Self.outputReply }
            return errorReply
        }
        let (group, _) = makeGroup(server)
        _ = try await group.connect(interface: "lo0", rescan: false)

        await #expect(throws: SpeakerError.rejected(speaker: "Fake", reply: errorReply)) {
            _ = try await group.setLevel(42)
        }
    }

    @Test("a scanned device that has no output is left out and its connection released")
    func nonSpeakerIsLeftOut() async throws {
        // Both devices are on the one fake server; the connection that asks first has no output.
        let nonSpeaker = OSAllocatedUnfairLock<ObjectIdentifier?>(initialState: nil)
        let server = try FakeSSCServer { line in
            let connection = ObjectIdentifier(Thread.current)
            let isNonSpeaker = nonSpeaker.withLock { first in
                if first == nil { first = connection }
                return first == connection
            }
            if isNonSpeaker && line.contains("audio") { return FakeSSCServer.notFoundReply }
            return FakeSSCServer.defaultReply(line)
        }
        let found = [Speaker(id: "a", address: "::1"), Speaker(id: "b", address: "::1")]
        let (group, directory) = makeGroup(server, stored: [], found: found)

        let outputs = try await group.connect(interface: "lo0", rescan: true)

        #expect(outputs.count == 1)
        #expect(directory.load().map(\.id) == outputs.map(\.id))
        #expect(server.waitUntil { server.openCount == 1 })
        #expect(try await group.setLevel(42).map(\.level) == [42])
    }

    // MARK: KH 750

    @Test("a KH 750 whose own output is out5 is read and set there")
    func kh750AtOut5() async throws {
        let server = try FakeSSCServer(reply: FakeSSCServer.kh750(version: "1_2_4", node: "out5"))
        let (group, _) = makeGroup(server)

        let read = try await group.connect(interface: "lo0", rescan: false)
        #expect(read == [SpeakerOutput(id: "fake", name: "Sub", level: 50, muted: false)])

        let lowered = try await group.setLevel(42)
        #expect(lowered.map(\.level) == [42])
        #expect(server.requests.last == #"{"audio":{"out5":{"level":42.0}}}"#)

        let muted = try await group.setMuted(true)
        #expect(muted == [SpeakerOutput(id: "fake", name: "Sub", level: 42, muted: true)])
        #expect(server.requests.last == #"{"audio":{"out5":{"mute":true}}}"#)

        // Every set was answered with the applied value, so the output was read once.
        #expect(server.requests.filter { $0.contains(#""level":null"#) } == [SSCMessage.outputQuery(.out5)])
        #expect(server.requests.filter { $0 == SSCMessage.versionQuery }.count == 1)
    }

    @Test("a KH 750 on firmware that keeps its output at out is read and set there", arguments: ["1_1_0", "2_0_3"])
    func kh750AtOut(version: String) async throws {
        let server = try FakeSSCServer(reply: FakeSSCServer.kh750(version: version, node: "out"))
        let (group, _) = makeGroup(server)

        _ = try await group.connect(interface: "lo0", rescan: false)
        let lowered = try await group.setLevel(42)

        #expect(lowered == [SpeakerOutput(id: "fake", name: "Sub", level: 42, muted: false)])
        #expect(server.requests.last == SSCMessage.setLevel(42))
    }

    @Test("a device that does not say what it is is treated as a plain speaker")
    func unknownProduct() async throws {
        let server = try FakeSSCServer { line in
            if line.contains(#""name":null"#) { return #"{"device":{"name":"Fake"}}"# }
            if line.contains(#""level":null"#) { return Self.outputReply }
            return FakeSSCServer.notFoundReply
        }
        let (group, _) = makeGroup(server)

        let outputs = try await group.connect(interface: "lo0", rescan: false)

        #expect(outputs.map(\.level) == [50])
        #expect(server.requests.last == SSCMessage.outputQuery())
    }

    @Test("a reply without a level is unexpected")
    func unexpectedReply() async throws {
        let server = try FakeSSCServer { line in
            line.contains(#""name":null"#) ? #"{"device":{"name":"Fake"}}"# : "{}"
        }
        let (group, _) = makeGroup(server)
        await #expect(throws: SpeakerError.unexpectedReply(speaker: "Fake")) {
            _ = try await group.connect(interface: "lo0", rescan: false)
        }
    }
}
