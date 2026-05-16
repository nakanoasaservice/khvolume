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
