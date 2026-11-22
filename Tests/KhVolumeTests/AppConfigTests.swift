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
        AppDefaults.saveConfig(config, to: defaults)
        #expect(AppDefaults.loadConfig(from: defaults) == config)
    }

    @Test("config saved with keys that no longer exist still loads")
    func unknownKeysAreIgnored() {
        let defaults = UserDefaults.makeForTesting()
        var config = AppConfig()
        config.networkInterface = "en15"
        AppDefaults.saveConfig(config, to: defaults)
        var stored = defaults.dictionary(forKey: AppDefaults.configKey) ?? [:]
        stored["hotkeyVolumeUp"] = "option+equal"
        defaults.set(stored, forKey: AppDefaults.configKey)
        #expect(AppDefaults.loadConfig(from: defaults) == config)
    }

    @Test("a config that lacks a setting is replaced with the defaults")
    func undecodableConfigIsReplaced() {
        let defaults = UserDefaults.makeForTesting()
        defaults.set(["interface": "en15", "maxVolumeLimit": 80.0], forKey: AppDefaults.configKey)

        #expect(AppDefaults.loadConfig(from: defaults) == AppConfig())
        #expect(defaults.dictionary(forKey: AppDefaults.configKey)?["interface"] == nil)
        #expect(defaults.dictionary(forKey: AppDefaults.configKey)?["volumeStep"] as? Double == 1)
    }

    @Test("missing config loads defaults")
    func missingConfig() {
        #expect(AppDefaults.loadConfig(from: .makeForTesting()) == AppConfig())
    }
}
