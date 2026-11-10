import Foundation

/// A view of the inbox the user defines themselves, like "Patto" or "Calendar": mail that carries
/// one of the chosen account labels, or comes from one of the chosen senders. Stored on this device
/// only; it never changes the real mailbox.
public struct InboxSplit: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// Names of the user's own account labels (Gmail labels), compared ignoring case.
    public var labelNames: [String]
    /// Full addresses ("a@b.com") or whole domains ("@b.com").
    public var senderPatterns: [String]

    public init(id: UUID = UUID(), name: String, labelNames: [String] = [], senderPatterns: [String] = []) {
        self.id = id
        self.name = name
        self.labelNames = labelNames
        self.senderPatterns = senderPatterns
    }

    public func matches(_ message: MailMessage) -> Bool {
        let have = Set(message.labels.map { $0.name.lowercased() })
        if labelNames.contains(where: { have.contains($0.lowercased()) }) { return true }
        let address = message.from.address.lowercased()
        return senderPatterns.contains { raw in
            let p = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !p.isEmpty else { return false }
            return p.hasPrefix("@") ? address.hasSuffix(p) : address == p
        }
    }
}

public struct LabelCount: Hashable, Sendable {
    public let name: String
    public let count: Int
}

public enum SplitSuggestions {
    /// The user's account labels seen on these messages, most used first.
    public static func labels(in messages: [MailMessage]) -> [LabelCount] {
        var counts: [String: Int] = [:]
        for m in messages { for l in m.labels { counts[l.name, default: 0] += 1 } }
        return counts.map { LabelCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.lowercased() < $1.name.lowercased() }
    }
}

/// Persists the splits as local JSON (never uploaded).
public struct InboxSplitStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("InboxSplits.json")
    }

    public func load() -> [InboxSplit] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([InboxSplit].self, from: data)) ?? []
    }

    public func save(_ splits: [InboxSplit]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(splits).write(to: fileURL, options: .atomic)
    }
}
