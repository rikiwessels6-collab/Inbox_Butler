import Foundation
#if canImport(Security)
import Security
#endif

/// Minimal Keychain wrapper for tokens and passwords.
/// This is the ONLY place secrets are stored. Never put them in SwiftData,
/// UserDefaults, the App Group container, or logs.
public struct KeychainStore: Sendable {
    public enum KeychainError: Error { case unavailable, status(Int32) }

    private let service: String

    public init(service: String = "com.example.InboxButler") {
        self.service = service
    }

    /// Saves (or replaces) a secret under `key`, e.g. "<accountID>.refreshToken".
    public func set(_ value: String, for key: String) throws {
        #if canImport(Security)
        let data = Data(value.utf8)
        let query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Readable after first unlock (so background sync works), never synced
        // to other devices or backups.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        #else
        throw KeychainError.unavailable
        #endif
    }

    public func get(_ key: String) throws -> String? {
        #if canImport(Security)
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.status(status)
        }
        return String(data: data, encoding: .utf8)
        #else
        throw KeychainError.unavailable
        #endif
    }

    public func remove(_ key: String) {
        #if canImport(Security)
        SecItemDelete(baseQuery(key) as CFDictionary)
        #endif
    }

    #if canImport(Security)
    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
    #endif
}
