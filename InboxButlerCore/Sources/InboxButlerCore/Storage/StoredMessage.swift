import Foundation
import SwiftData

/// SwiftData row mirroring `MailMessage`. Internal to Core: the rest of the app
/// only sees `MailMessage` through `MessageCache`. Holds mail metadata only,
/// never tokens or passwords (those are Keychain-only).
@Model
final class StoredMessage {
    @Attribute(.unique) var id: String
    var accountID: UUID
    var providerMessageID: String
    var threadID: String?
    var fromName: String?
    var fromAddress: String
    var toJSON: Data
    var subject: String
    var snippet: String
    var receivedAt: Date
    var isRead: Bool
    /// Marked read inside this app only. Never written back to the mailbox.
    var readLocally: Bool
    var attachmentsJSON: Data
    var importance: Double?
    var awaitingReply: Bool

    init(_ m: MailMessage) {
        id = m.id
        accountID = m.accountID
        providerMessageID = m.providerMessageID
        threadID = m.threadID
        fromName = m.from.name
        fromAddress = m.from.address
        toJSON = (try? JSONEncoder().encode(m.to)) ?? Data()
        subject = m.subject
        snippet = m.snippet
        receivedAt = m.receivedAt
        isRead = m.isRead
        readLocally = false
        attachmentsJSON = (try? JSONEncoder().encode(m.attachments)) ?? Data()
        importance = m.importance
        awaitingReply = m.awaitingReply
    }

    /// Refreshes server-owned fields; keeps local-only state (importance, readLocally).
    func update(from m: MailMessage) {
        threadID = m.threadID
        fromName = m.from.name
        fromAddress = m.from.address
        toJSON = (try? JSONEncoder().encode(m.to)) ?? Data()
        subject = m.subject
        snippet = m.snippet
        receivedAt = m.receivedAt
        isRead = m.isRead
        attachmentsJSON = (try? JSONEncoder().encode(m.attachments)) ?? Data()
        if let imp = m.importance { importance = imp }
        awaitingReply = awaitingReply || m.awaitingReply
    }

    var asMessage: MailMessage {
        MailMessage(accountID: accountID, providerMessageID: providerMessageID, threadID: threadID,
                    from: MailAddress(name: fromName, address: fromAddress),
                    to: (try? JSONDecoder().decode([MailAddress].self, from: toJSON)) ?? [],
                    subject: subject, snippet: snippet, receivedAt: receivedAt,
                    isRead: isRead || readLocally,
                    attachments: (try? JSONDecoder().decode([AttachmentInfo].self, from: attachmentsJSON)) ?? [],
                    importance: importance, awaitingReply: awaitingReply)
    }
}
