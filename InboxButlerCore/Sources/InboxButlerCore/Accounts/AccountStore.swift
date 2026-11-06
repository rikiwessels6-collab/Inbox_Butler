import Foundation

/// Persists the list of connected accounts (no secrets) as local JSON.
public struct AccountStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("Accounts.json")
    }

    public func load() -> [MailAccount] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([MailAccount].self, from: data)) ?? []
    }

    public func save(_ accounts: [MailAccount]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(accounts).write(to: fileURL, options: .atomic)
    }
}
