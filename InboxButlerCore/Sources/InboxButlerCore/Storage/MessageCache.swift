import Foundation
import SwiftData

/// Offline-first local copy of mail (SwiftData). The UI shows this immediately at
/// launch and whenever the network is down; sync keeps it up to date.
@MainActor
public final class MessageCache {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        container = try ModelContainer(for: StoredMessage.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    /// All cached messages, newest first.
    public func load() -> [MailMessage] {
        let rows = (try? context.fetch(FetchDescriptor<StoredMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? []
        return rows.map(\.asMessage)
    }

    /// Applies one account's fresh fetch: inserts/updates rows, and removes cached
    /// rows that are newer than the oldest fetched message but missing from the
    /// fetch (they were deleted or moved elsewhere). Older rows are kept.
    public func sync(accountID: UUID, fetched: [MailMessage]) {
        let rows = (try? context.fetch(FetchDescriptor<StoredMessage>(predicate: #Predicate { $0.accountID == accountID }))) ?? []
        var byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for m in fetched {
            if let row = byID[m.id] { row.update(from: m) } else {
                let row = StoredMessage(m)
                context.insert(row)
                byID[m.id] = row
            }
        }
        // An empty fetch could be an outage or a genuinely empty inbox: delete nothing.
        if let oldest = fetched.map(\.receivedAt).min() {
            let fetchedIDs = Set(fetched.map(\.id))
            for row in rows where row.receivedAt >= oldest && !fetchedIDs.contains(row.id) { context.delete(row) }
        }
        try? context.save()
    }

    public func markReadLocally(_ id: String) {
        let rows = (try? context.fetch(FetchDescriptor<StoredMessage>(predicate: #Predicate { $0.id == id }))) ?? []
        rows.first?.readLocally = true
        try? context.save()
    }

    /// Deletes everything cached for an account (used when removing it).
    public func remove(accountID: UUID) {
        let rows = (try? context.fetch(FetchDescriptor<StoredMessage>(predicate: #Predicate { $0.accountID == accountID }))) ?? []
        rows.forEach(context.delete)
        try? context.save()
    }

    /// Keeps the newest `count` messages overall.
    public func prune(keepNewest count: Int = 1000) {
        let rows = (try? context.fetch(FetchDescriptor<StoredMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? []
        guard rows.count > count else { return }
        rows.dropFirst(count).forEach(context.delete)
        try? context.save()
    }
}
