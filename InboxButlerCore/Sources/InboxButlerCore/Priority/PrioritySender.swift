import Foundation

/// A sender the user has marked as high priority. Only mail from these senders
/// triggers notifications and is pinned to the top of the widget.
///
/// `pattern` is either a full address ("boss@work.com") or a whole domain
/// ("@work.com"), always stored lowercased.
public struct PrioritySender: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let pattern: String
    public var note: String?

    /// Returns nil if `input` is not a valid address or "@domain".
    public init?(input: String, note: String? = nil, id: UUID = UUID()) {
        let p = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if p.hasPrefix("@") {
            let domain = p.dropFirst()
            guard domain.contains("."), !domain.contains("@"), !domain.contains(" ") else { return nil }
        } else {
            let parts = p.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !p.contains(" ") else { return nil }
        }
        self.id = id
        self.pattern = p
        self.note = note
    }

    public var isDomainRule: Bool { pattern.hasPrefix("@") }

    public func matches(_ address: String) -> Bool {
        let a = address.lowercased()
        return isDomainRule ? a.hasSuffix(pattern) : a == pattern
    }
}

extension Collection where Element == PrioritySender {
    /// True if any rule matches this address.
    public func contains(address: String) -> Bool { contains { $0.matches(address) } }
}

/// Persists the priority list as local JSON (never uploaded).
public struct PrioritySenderStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("PrioritySenders.json")
    }

    public func load() -> [PrioritySender] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PrioritySender].self, from: data)) ?? []
    }

    public func save(_ senders: [PrioritySender]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(senders).write(to: fileURL, options: .atomic)
    }
}
