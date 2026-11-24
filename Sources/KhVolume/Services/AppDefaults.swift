import Foundation

/// App settings, stored in UserDefaults. (The scanned speaker list is `SpeakerDirectory`.)
enum AppDefaults {
    static let configKey = "config"

    static func loadConfig(from defaults: UserDefaults = .standard) -> AppConfig {
        // Stored as a plist dictionary so `defaults read` shows readable values.
        guard let object = defaults.object(forKey: configKey),
              let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0),
              let config = try? PropertyListDecoder().decode(AppConfig.self, from: data)
        else {
            // Nothing stored, or stored by a version with other settings: start over in the
            // current format instead of migrating.
            let config = AppConfig()
            saveConfig(config, to: defaults)
            return config
        }
        return config
    }

    static func saveConfig(_ config: AppConfig, to defaults: UserDefaults = .standard) {
        guard let data = try? PropertyListEncoder().encode(config),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return }
        defaults.set(object, forKey: configKey)
    }
}
