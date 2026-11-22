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
}
