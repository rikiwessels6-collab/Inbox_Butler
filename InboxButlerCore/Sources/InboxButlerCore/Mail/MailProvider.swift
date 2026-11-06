import Foundation

public enum Mailbox: String, Codable, Sendable {
    case inbox
    /// Used only to learn the user's writing style.
    case sent
}

/// Opaque per-account position for incremental sync (Gmail historyId,
/// Graph deltaLink, IMAP UIDVALIDITY+UID, ...).
public struct SyncCursor: Hashable, Codable, Sendable {
    public var value: String
    public init(_ value: String) { self.value = value }
}

public struct MailPage: Sendable {
    public var messages: [MailMessage]
    /// Pass back as `since:` on the next call.
    public var nextCursor: SyncCursor?
    public init(messages: [MailMessage], nextCursor: SyncCursor? = nil) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
}

public enum MailProviderError: Error, LocalizedError, Sendable {
    case notImplemented(String)
    case notAuthorized
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let what): return "\(what) is not wired up yet."
        case .notAuthorized: return "Sign-in required."
        case .network(let msg): return msg
        }
    }
}

/// One mail backend (Gmail, Microsoft Graph, IMAP...).
///
/// SAFETY: this protocol is intentionally READ-ONLY. There is no send, delete,
/// archive, move or flag method. Anything that changes a mailbox must be a
/// separate protocol, called only from an explicit user action.
public protocol MailProvider: Sendable {
    var account: MailAccount { get }

    /// Interactive sign-in. Stores credentials in the Keychain, never returns them.
    func authorize() async throws

    /// Fetch messages newer than `cursor` (or the latest `limit` if nil).
    func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage

    /// The message text (plain text; HTML is converted). Fetched on demand when a
    /// message is opened or scanned, not during sync.
    func fetchBody(for message: MailMessage) async throws -> String

    /// The original HTML of the message, if it has one (for the formatted view).
    func fetchHTMLBody(for message: MailMessage) async throws -> String?

    /// Download one attachment's bytes (on demand, not during sync).
    func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data
}

extension MailProvider {
    /// Providers without HTML support just say there is none.
    public func fetchHTMLBody(for message: MailMessage) async throws -> String? { nil }
}
