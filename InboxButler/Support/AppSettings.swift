import Foundation

/// User preferences, stored on the device (UserDefaults). Views read the same
/// keys with @AppStorage.
enum AppSettings {
    static let lockKey = "appLockEnabled"
    static let redactKey = "widgetRedacted"
    static let timeSensitiveKey = "timeSensitiveAlerts"
    static let followUpsKey = "followUpReminders"
    static let briefKey = "morningBrief"
    static let dismissedSuggestionsKey = "dismissedSuggestions"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
