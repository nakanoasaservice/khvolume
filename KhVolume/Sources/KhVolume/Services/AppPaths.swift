import Foundation

enum AppPaths {
    static let supportName = "KHVolume"

    static var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(supportName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL {
        appSupportURL.appendingPathComponent("config.json")
    }

    static var khtoolCacheURL: URL {
        appSupportURL.appendingPathComponent("khtool.json")
    }

    /// True when a non-empty speaker cache exists (avoids rescan on every popover open).
    static var hasSpeakerCache: Bool {
        guard let data = try? Data(contentsOf: khtoolCacheURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return !object.isEmpty
    }

    static func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return config
    }

    static func saveConfig(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    #if DEBUG
    static var useBundledHelperOnly: Bool {
        ProcessInfo.processInfo.environment["KHVOL_USE_BUNDLED"] == "1"
    }
    #endif
}
