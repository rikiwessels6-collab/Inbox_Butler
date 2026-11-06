import Foundation

/// Result of one refresh across all accounts. A failing account never blocks
/// the others; its error is reported alongside the merged messages.
public struct SyncResult: Sendable {
    public var messages: [MailMessage]
    public var errors: [UUID: String]   // accountID -> readable error
}

/// Fans out to every provider, merges results into one newest-first list.
public actor SyncEngine {
    private let providers: [any MailProvider]
    private var cursors: [UUID: SyncCursor] = [:]

    public init(providers: [any MailProvider]) {
        self.providers = providers
    }

    public func refresh(limitPerAccount: Int = 50) async -> SyncResult {
        let startCursors = cursors
        var all: [MailMessage] = []
        var errors: [UUID: String] = [:]

        await withTaskGroup(of: (UUID, Result<MailPage, Error>).self) { group in
            for provider in providers {
                let id = provider.account.id
                let cursor = startCursors[id]
                group.addTask {
                    do {
                        let page = try await provider.fetchMessages(in: .inbox, since: cursor, limit: limitPerAccount)
                        return (id, .success(page))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let page):
                    all.append(contentsOf: page.messages)
                    if let next = page.nextCursor { cursors[id] = next }
                case .failure(let error):
                    errors[id] = error.localizedDescription
                }
            }
        }

        // De-duplicate by unified id, newest first.
        var seen = Set<String>()
        let merged = all
            .sorted { $0.receivedAt > $1.receivedAt }
            .filter { seen.insert($0.id).inserted }
        return SyncResult(messages: merged, errors: errors)
    }
}
