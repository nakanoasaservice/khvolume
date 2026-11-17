import Foundation
import Testing
@testable import KhVolume

@Suite("SSCSpeakerPool — persistent connections")
struct SSCSpeakerPoolTests {

    private func makePool(_ server: FakeSSCServer) -> SSCSpeakerPool {
        SSCSpeakerPool(port: server.port, timeout: 1)
    }

    @Test("reuses one connection per speaker and asks the name once")
    func reusesConnection() async throws {
        let server = try FakeSSCServer()
        let pool = makePool(server)
        for _ in 0..<3 {
            let replies = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo0")
            #expect(replies == [.init(name: "Fake", reply: #"{"audio":{"out":{"level":50.0,"mute":false}}}"#)])
        }
        #expect(server.acceptedCount == 1)
        #expect(server.requests.filter { $0 == SSCMessage.deviceNameQuery }.count == 1)
    }

    @Test("reconnects once when the reused connection was dropped")
    func reconnectsAfterDrop() async throws {
        let server = try FakeSSCServer()
        let pool = makePool(server)
        _ = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo0")
        server.dropClients()
        #expect(server.waitUntil { server.openCount == 0 })

        let replies = try await pool.send(SSCMessage.setMuted(true), to: ["::1"], interface: "lo0")
        #expect(replies.map(\.reply) == [SSCMessage.setMuted(true)])
        #expect(server.acceptedCount == 2)
    }

    @Test("closeAll releases the device's connection")
    func closeAllReleases() async throws {
        let server = try FakeSSCServer()
        let pool = makePool(server)
        _ = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo0")
        #expect(server.openCount == 1)
        pool.closeAll()
        #expect(server.waitUntil { server.openCount == 0 })
        #expect(pool.speakerCount == 0)
    }

    @Test("changing the interface replaces existing connections")
    func interfaceChangeReconnects() async throws {
        let server = try FakeSSCServer()
        let pool = makePool(server)
        _ = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo0")
        _ = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo1")
        #expect(server.acceptedCount == 2)
        #expect(server.waitUntil { server.openCount == 1 })
    }

    @Test("unreachable speaker reports it is not online")
    func unreachable() async throws {
        let server = try FakeSSCServer()
        let port = server.port
        server.stop()
        let pool = SSCSpeakerPool(port: port, timeout: 1)
        do {
            _ = try await pool.send(SSCMessage.outputQuery, to: ["::1"], interface: "lo0")
            Issue.record("expected failure")
        } catch {
            #expect(error.errorDescription == "device ::1 is not online")
        }
    }
}
