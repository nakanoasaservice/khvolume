import Foundation

extension UserDefaults {
    /// A fresh, empty suite per call so tests never touch the app's real defaults.
    static func makeForTesting() -> UserDefaults {
        let name = "KhVolumeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
