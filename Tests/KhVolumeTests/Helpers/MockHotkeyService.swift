@testable import KhVolume

@MainActor
final class MockHotkeyService: HotkeyService {
    private(set) var registerCallCount = 0

    func register() {
        registerCallCount += 1
    }
}
