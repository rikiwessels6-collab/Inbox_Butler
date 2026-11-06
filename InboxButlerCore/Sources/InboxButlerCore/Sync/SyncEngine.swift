import Foundation

/// Result of one refresh across all accounts. A failing account never blocks
/// the others; its error is reported alongside the merged messages.
public struct SyncResult: Sendable {
    public var messages: [MailMessage]
    /// Recently sent mail (used for reply tracking and writing-style hints).
    public var sent: [MailMessage]
    public var errors: [UUID: String]   // accountID -> readable error
}

/// Fans out to every provider, merges results into one newest-first list.
public actor SyncEngine {
    private let providers: [any MailProvider]
    private var cursors: [UUID: SyncCursor] = [:]

    public init(providers: [any MailProvider]) {
        self.providers = providers
    }

    private struct Outcome: Sendable {
        let accountID: UUID
        let inbox: Result<MailPage, Error>
        let sent: [MailMessage]
    }

    public func refresh(limitPerAccount: Int = 50, sentLimit: Int = 30) async -> SyncResult {
        let startCursors = cursors
        var all: [MailMessage] = []
        var sent: [MailMessage] = []
        var errors: [UUID: String] = [:]
        var newCursors: [UUID: SyncCursor] = [:]

        await withTaskGroup(of: Outcome.self) { group in
            for provider in providers {
                let id = provider.account.id
                let cursor = startCursors[id]
                group.addTask {
                    let inbox: Result<MailPage, Error>
                    do {
                        inbox = .success(try await provider.fetchMessages(in: .inbox, since: cursor, limit: limitPerAccount))
                    } catch {
                        return Outcome(accountID: id, inbox: .failure(error), sent: [])
                    }
                    // Sent mail is best effort: a failure here never fails the account.
                    let sentPage = try? await provider.fetchMessages(in: .sent, since: nil, limit: sentLimit)
                    return Outcome(accountID: id, inbox: inbox, sent: sentPage?.messages ?? [])
                }
            }
            for await outcome in group {
                switch outcome.inbox {
                case .success(let page):
                    all.append(contentsOf: page.messages)
                    sent.append(contentsOf: outcome.sent)
                    if let next = page.nextCursor { newCursors[outcome.accountID] = next }
                case .failure(let error):
                    errors[outcome.accountID] = error.localizedDescription
                }
            }
        }
        cursors.merge(newCursors) { _, new in new }

        // De-duplicate by unified id, newest first.
        var seen = Set<String>()
        let merged = all
            .sorted { $0.receivedAt > $1.receivedAt }
            .filter { seen.insert($0.id).inserted }
        return SyncResult(messages: merged, sent: sent.sorted { $0.receivedAt > $1.receivedAt }, errors: errors)
    }
}
