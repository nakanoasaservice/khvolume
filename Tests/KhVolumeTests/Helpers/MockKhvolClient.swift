@testable import KhVolume

final class MockKhvolClient: KhvolClientProtocol, @unchecked Sendable {
    var jsonStatusResult: Result<KhvolJSONStatus, KhvolError> = .success(.stub())
    var setLevelResult: Result<KhvolJSONStatus, KhvolError> = .success(.stub())
    var setMutedResult: Result<KhvolJSONStatus, KhvolError> = .success(.stub())
    var interfacesResult: Result<[NetworkInterfaceInfo], KhvolError> = .success([])
    var scanResult: Result<Int, KhvolError> = .success(1)

    private(set) var jsonStatusCallCount = 0
    private(set) var setLevelCallCount = 0
    private(set) var lastSetLevelArg: Double?
    private(set) var lastSetMutedArg: Bool?

    func jsonStatus() async throws(KhvolError) -> KhvolJSONStatus {
        jsonStatusCallCount += 1
        return try jsonStatusResult.get()
    }

    func setLevel(_ level: Double) async throws(KhvolError) -> KhvolJSONStatus {
        setLevelCallCount += 1
        lastSetLevelArg = level
        return try setLevelResult.get()
    }

    func setMuted(_ muted: Bool) async throws(KhvolError) -> KhvolJSONStatus {
        lastSetMutedArg = muted
        return try setMutedResult.get()
    }

    func interfaces() async throws(KhvolError) -> [NetworkInterfaceInfo] {
        try interfacesResult.get()
    }

    func scan() async throws(KhvolError) -> Int {
        try scanResult.get()
    }
}

extension KhvolJSONStatus {
    static func stub(
        devices: [String: KhvolJSONStatus.DeviceInfo] = [:],
        levels: [Double] = [50],
        muted: Bool = false,
        balanced: Bool = true
    ) -> KhvolJSONStatus {
        KhvolJSONStatus(devices: devices, levels: levels, muted: muted, balanced: balanced)
    }
}
