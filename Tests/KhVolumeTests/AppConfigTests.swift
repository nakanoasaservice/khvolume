import Foundation
import Testing
@testable import KhVolume

@Suite("AppConfig — effectiveMax")
struct AppConfigTests {

    @Test("effectiveMax is capped at 120", arguments: [
        (120.0, 120.0),
        (150.0, 120.0),
        (200.0, 120.0),
    ] as [(Double, Double)])
    func effectiveMaxCappedAt120(limit: Double, expected: Double) {
        var config = AppConfig()
        config.maxVolumeLimit = limit
        #expect(config.effectiveMax == expected)
    }

    @Test("effectiveMax floors at 0", arguments: [
        (0.0, 0.0),
        (-1.0, 0.0),
        (-100.0, 0.0),
    ] as [(Double, Double)])
    func effectiveMaxFloorsAtZero(limit: Double, expected: Double) {
        var config = AppConfig()
        config.maxVolumeLimit = limit
        #expect(config.effectiveMax == expected)
    }

    @Test("effectiveMax passes through valid range", arguments: [
        (1.0, 1.0),
        (50.0, 50.0),
        (100.0, 100.0),
        (119.9, 119.9),
    ] as [(Double, Double)])
    func effectiveMaxPassesThrough(limit: Double, expected: Double) {
        var config = AppConfig()
        config.maxVolumeLimit = limit
        #expect(config.effectiveMax == expected)
    }
}

@Suite("AppDefaults — config persistence")
struct AppDefaultsTests {

    @Test("config round-trips through UserDefaults")
    func roundTrip() {
        let defaults = UserDefaults.makeForTesting()
        var config = AppConfig()
        config.networkInterface = "en15"
        config.maxVolumeLimit = 75
        config.hotkeyMuteToggle = "control+option+m"
        AppDefaults.saveConfig(config, to: defaults)
        #expect(AppDefaults.loadConfig(from: defaults) == config)
    }

    @Test("missing config loads defaults")
    func missingConfig() {
        #expect(AppDefaults.loadConfig(from: .makeForTesting()) == AppConfig())
    }
}
