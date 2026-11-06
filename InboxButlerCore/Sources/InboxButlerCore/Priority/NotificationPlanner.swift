import Foundation

/// What a notification will say. Built on-device from mail already downloaded.
public struct PlannedNotification: Identifiable, Equatable, Sendable {
    public let id: String          // MailMessage.id
    public let title: String       // sender
    public let subtitle: String    // account label
    public let body: String        // subject
}

/// Decides which new messages deserve a notification. Pure logic, no UI.
/// Rule: unread + sender is on the priority list + not already notified.
public enum NotificationPlanner {
    /// At most this many per run, so a burst cannot spam. The rest are picked up next run.
    public static let maxPerRun = 5

    public static func plan(messages: [MailMessage], accounts: [MailAccount],
                            priority: [PrioritySender],
                            alreadyNotified: Set<String>) -> [PlannedNotification] {
        guard !priority.isEmpty else { return [] }
        let labels = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.label) })
        return messages
            .filter { !$0.isRead && !alreadyNotified.contains($0.id) && priority.contains(address: $0.from.address) }
            .sorted { $0.receivedAt > $1.receivedAt }
            .prefix(maxPerRun)
            .map { PlannedNotification(id: $0.id, title: $0.from.display,
                                       subtitle: labels[$0.accountID] ?? "", body: $0.subject) }
    }
}

/// Remembers which message ids have been handled so nothing notifies twice.
/// `load()` returns nil on the very first run, which the app uses to seed the
/// list silently (so installing the app doesn't buzz for old mail).
public struct NotifiedStore: Sendable {
    private let fileURL: URL
    private let limit = 2000

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("NotifiedIDs.json")
    }

    public func load() -> Set<String>? {
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(ids)
    }

    /// Appends ids and trims the file to the most recent `limit` entries.
    public func add(_ ids: [String]) {
        var all = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        all.append(contentsOf: ids.filter { !all.contains($0) })
        if all.count > limit { all.removeFirst(all.count - limit) }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
    }
}
