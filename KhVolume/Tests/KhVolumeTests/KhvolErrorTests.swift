import Testing
@testable import KhVolume

@Suite("KhvolError — errorDescription")
struct KhvolErrorTests {

    @Test("helperMissing has description")
    func helperMissing() {
        #expect(KhvolError.helperMissing.errorDescription == "khvol helper not found")
    }

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
        #expect(KhvolError.parseFailed.errorDescription == "Failed to parse khvol output")
    }

    @Test("timedOut has description")
    func timedOut() {
        #expect(KhvolError.timedOut.errorDescription == "khvol timed out")
    }

    @Test("all cases have non-nil errorDescription")
    func allCasesNonNil() {
        let cases: [KhvolError] = [
            .helperMissing,
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
