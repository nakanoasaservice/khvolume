import Foundation
import Testing
@testable import KhVolume

@Suite("AppDefaults — config persistence")
struct AppDefaultsTests {

    @Test("config round-trips through UserDefaults")
    func roundTrip() {
        let defaults = UserDefaults.makeForTesting()
        var config = AppConfig()
        config.networkInterface = "en15"
        config.levelLimit = 75
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

    @Test("a config stored before the properties were renamed still loads")
    func storedUnderEarlierNames() {
        let defaults = UserDefaults.makeForTesting()
        defaults.set(
            [
                "interface": "en15", "maxVolumeLimit": 70.0, "volumeStep": 3.0,
                "allowForceOnMismatch": true, "launchAtLogin": true,
            ],
            forKey: AppDefaults.configKey
        )

        let config = AppDefaults.loadConfig(from: defaults)

        #expect(config.networkInterface == "en15")
        #expect(config.levelLimit == 70)
        #expect(config.levelStep == 3)
        #expect(config.allowsIncreaseWhileUnbalanced)
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
