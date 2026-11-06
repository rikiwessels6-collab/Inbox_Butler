import Foundation

/// STUB. Planned: IMAP over TLS (iCloud needs an app-specific password).
/// Tokens/passwords go to `KeychainStore` only. Read-only access.
public struct IMAPProvider: MailProvider {
    public let account: MailAccount
    public init(account: MailAccount) { self.account = account }

    public func authorize() async throws {
        throw MailProviderError.notImplemented("IMAP sign-in")
    }
    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        throw MailProviderError.notImplemented("IMAP sync")
    }
    public func fetchBody(for message: MailMessage) async throws -> String {
        throw MailProviderError.notImplemented("IMAP message body")
    }
    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        throw MailProviderError.notImplemented("IMAP attachments")
    }
}
