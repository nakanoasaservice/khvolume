import Foundation

/// App settings and the scanned speaker list, stored in UserDefaults.
enum AppDefaults {
    static let configKey = "config"
    static let speakersKey = "speakers"

    /// True when a scan has stored at least one speaker (avoids rescan on every popover open).
    static var hasSpeakerCache: Bool {
        !SpeakerDirectory().load().isEmpty
    }

    static func loadConfig(from defaults: UserDefaults = .standard) -> AppConfig {
        // Stored as a plist dictionary so `defaults read` shows readable values.
        guard let object = defaults.object(forKey: configKey),
              let data = try? PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0),
              let config = try? PropertyListDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
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
