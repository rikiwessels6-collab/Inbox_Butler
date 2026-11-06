import Foundation

/// Where secrets (tokens, passwords) live. Production = `KeychainStore`.
/// Tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String)
}

extension KeychainStore: SecretStore {}

/// Non-persistent store for tests and previews. Never use for real secrets.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    public init() {}

    public func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
    public func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}
