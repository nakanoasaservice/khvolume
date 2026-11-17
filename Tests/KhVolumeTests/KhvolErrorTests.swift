import Testing
@testable import KhVolume

@Suite("KhvolError — errorDescription")
struct KhvolErrorTests {

    @Test("commandFailed passes through message")
    func commandFailed() {
        #expect(KhvolError.commandFailed("something went wrong").errorDescription == "something went wrong")
    }

    @Test("deviceError passes through message")
    func deviceError() {
        #expect(KhvolError.deviceError("device disconnected").errorDescription == "device disconnected")
    }

    @Test("parseFailed has description")
    func parseFailed() {
        #expect(KhvolError.parseFailed.errorDescription == "Failed to parse speaker response")
    }

    @Test("timedOut has description")
    func timedOut() {
        #expect(KhvolError.timedOut.errorDescription == "Speaker did not respond in time")
    }

    @Test("all cases have non-nil errorDescription")
    func allCasesNonNil() {
        let cases: [KhvolError] = [
            .commandFailed("x"),
            .deviceError("y"),
            .parseFailed,
            .timedOut,
        ]
        for error in cases {
            #expect(error.errorDescription != nil, "Expected non-nil description for \(error)")
        }
    }
}
