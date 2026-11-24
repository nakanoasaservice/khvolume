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

    @Test("scan, read, set level, mute, and many reads over the same connections")
    func endToEnd() async throws {
        let interfaces = NetworkInterfaceLister.list()
        print("interfaces:", interfaces.map { "\($0.name)=\($0.label)/\($0.isActive ? "active" : "inactive")" })
        #expect(interfaces.contains { $0.name == interface && $0.isActive })

        let directory = SpeakerDirectory(defaults: .makeForTesting())
        let group = SSCSpeakerGroup(directory: directory)

        let start = ContinuousClock.now
        let initial = try await group.connect(interface: interface, rescan: true)
        print("scan found \(initial.count) speakers in \(ContinuousClock.now - start):", initial)
        #expect(!initial.isEmpty)
        let originalLevel = initial[0].level

        // A set must be answered with the applied value; otherwise every set costs a second round trip.
        for speaker in directory.load() {
            let link = SpeakerLink(speaker: speaker, interface: interface)
            let reply = try await link.send { SSCMessage.setLevel(originalLevel, node: $0) }.get()
            print("set reply from \(reply.name):", reply.text)
            #expect(reply.output?.level != nil)
        }

        let setStart = ContinuousClock.now
        let lowered = try await group.setLevel(originalLevel - 1)
        print("set level: \(ContinuousClock.now - setStart)")
        #expect(lowered.allSatisfy { abs($0.level - (originalLevel - 1)) < 0.05 })
        // What the set replies said must match what the speakers report when asked.
        #expect(try await group.connect(interface: interface, rescan: false) == lowered)

        let muted = try await group.setMuted(true)
        #expect(muted.isMuted)
        #expect(try await group.connect(interface: interface, rescan: false) == muted)
        let unmuted = try await group.setMuted(initial.isMuted)
        #expect(unmuted.isMuted == initial.isMuted)

        let restored = try await group.setLevel(originalLevel)
        #expect(restored.allSatisfy { abs($0.level - originalLevel) < 0.05 })

        let burstStart = ContinuousClock.now
        for _ in 0..<30 {
            _ = try await group.connect(interface: interface, rescan: false)
        }
        print("30 reads: \(ContinuousClock.now - burstStart)")
    }
}
