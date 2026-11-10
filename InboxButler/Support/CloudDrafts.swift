import Foundation
import InboxButlerCore

/// The OPTIONAL cloud-drafting switch. Off by default. When on, the one email being replied to (and a
/// short summary of the writer's style) is sent to Anthropic's API to write the draft, using the
/// person's OWN API key, which lives only in this phone's Keychain.
enum CloudDrafts {
    enum Mode: String, CaseIterable, Identifiable {
        case off, whenNeeded, always
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return "Off (on this phone only)"
            case .whenNeeded: return "Only if Apple Intelligence isn't available"
            case .always: return "Always"
            }
        }
    }

    static let modeKey = "cloudDraftMode"
    static let modelKey = "cloudDraftModel"

    static var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .off }
    static var model: CloudModel { CloudModel(rawValue: UserDefaults.standard.string(forKey: modelKey) ?? "") ?? .opus }

    static var apiKey: String? {
        guard let key = try? KeychainStore().get(CloudAIService.keychainKey), !key.isEmpty else { return nil }
        return key
    }
    static var hasKey: Bool { apiKey != nil }

    static func saveKey(_ key: String) throws {
        try KeychainStore().set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: CloudAIService.keychainKey)
    }
    static func removeKey() { KeychainStore().remove(CloudAIService.keychainKey) }

    /// The cloud service to use for this draft, or nil to stay on the phone.
    static func service(onDeviceAvailable: Bool) -> CloudAIService? {
        guard let key = apiKey else { return nil }
        switch mode {
        case .off: return nil
        case .whenNeeded: return onDeviceAvailable ? nil : CloudAIService(apiKey: key, model: model)
        case .always: return CloudAIService(apiKey: key, model: model)
        }
    }
}
