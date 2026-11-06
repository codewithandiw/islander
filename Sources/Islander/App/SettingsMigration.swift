import Foundation

/// Copies preferences and focus history saved under earlier bundle IDs, so changing
/// the bundle ID does not reset the user's settings. The old preferences file is left
/// in place, so going back to an older build still works.
enum SettingsMigration {
    private static let legacyDomains = ["dev.islander.Islander"]
    private static let doneKey = "migration.legacyDomainsCopied"

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let current = Bundle.main.bundleIdentifier
        for domain in legacyDomains where domain != current {
            guard let old = defaults.persistentDomain(forName: domain) else { continue }
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
