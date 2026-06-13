// Export every OpenDisplay UserDefaults key to a JSON file and import them back, so a
// setup can be moved between machines or kept as a backup - BetterDisplay's settings
// export/import. Filters to the app's own key prefixes (never system globals), and uses
// JSONSerialization so values round-trip as the same String/Number/Array types
// UserDefaults stores. The caller reloads the model after an import to apply live.
// NOT responsible for: applying imported values (DisplayModel.reloadFromDefaults does)
// or cross-version schema migration.

import Foundation

enum SettingsPortability {
    // Every persisted key starts with one of these (display-scoped keys append the id).
    private static let prefixes = ["looksW.", "brightness.", "warmth.", "contrast.", "name.",
                                   "favorites.", "hardwareDDC.", "protectConfig.",
                                   "virtual.", "schedule.", "idle.", "preventSleep.", "preset."]

    private static func isOurs(_ key: String) -> Bool { prefixes.contains { key.hasPrefix($0) } }

    static func exportData() throws -> Data {
        let ours = UserDefaults.standard.dictionaryRepresentation().filter { isOurs($0.key) }
        return try JSONSerialization.data(withJSONObject: ours, options: [.prettyPrinted, .sortedKeys])
    }

    /// Write the recognized keys into UserDefaults; returns how many were applied.
    @discardableResult
    static func importData(_ data: Data) -> Int {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        var applied = 0
        for (key, value) in obj where isOurs(key) {
            UserDefaults.standard.set(value, forKey: key)
            applied += 1
        }
        return applied
    }
}
