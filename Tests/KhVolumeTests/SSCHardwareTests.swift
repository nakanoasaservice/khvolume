import Foundation
import Testing
@testable import KhVolume

/// End-to-end checks against real speakers. Skipped unless an interface is given:
///
///     TEST_RUNNER_KHVOL_HARDWARE_INTERFACE=en15 xcodebuild test … -only-testing:KhVolumeTests/SSCHardwareTests
///
/// Levels and mute are restored at the end; muting is audible for a moment.
@Suite(
    "SSC hardware (real speakers)",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["KHVOL_HARDWARE_INTERFACE"] != nil)
)
struct SSCHardwareTests {
    private let interface = ProcessInfo.processInfo.environment["KHVOL_HARDWARE_INTERFACE"] ?? ""

    @Test("scan, read, set level, mute, and many requests over pooled connections")
    func endToEnd() async throws {
        let pool = SSCSpeakerPool()
        let client = KhvolClient(interface: interface, speakers: SpeakerDirectory(defaults: .makeForTesting()), pool: pool)

        let interfaces = try await client.interfaces()
        print("interfaces:", interfaces.map { "\($0.name)=\($0.label)/\($0.status)" })
        #expect(interfaces.contains { $0.name == interface && $0.status == "active" })

        let start = ContinuousClock.now
        let count = try await client.scan()
        print("scan found \(count) speakers in \(ContinuousClock.now - start)")
        #expect(count > 0)

        let initial = try await client.jsonStatus()
        print("initial:", initial.devices)
        let originalLevel = initial.levels[0]

        let lowered = try await client.setLevel(originalLevel - 1)
        #expect(lowered.levels.allSatisfy { abs($0 - (originalLevel - 1)) < 0.05 })

        let muted = try await client.setMuted(true)
        #expect(muted.muted)
        let unmuted = try await client.setMuted(initial.muted)
        #expect(unmuted.muted == initial.muted)

        let restored = try await client.setLevel(originalLevel)
        #expect(restored.levels.allSatisfy { abs($0 - originalLevel) < 0.05 })

        let burstStart = ContinuousClock.now
        for _ in 0..<30 {
            _ = try await client.jsonStatus()
        }
        print("30 status reads: \(ContinuousClock.now - burstStart)")
        #expect(pool.speakerCount == count)
    }
}
