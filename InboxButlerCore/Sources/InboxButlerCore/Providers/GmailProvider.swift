import Foundation

/// STUB. Planned: Gmail REST API (gmail.readonly scope), OAuth 2.0 + PKCE.
/// Tokens/passwords go to `KeychainStore` only. Read-only access.
public struct GmailProvider: MailProvider {
    public let account: MailAccount
    public init(account: MailAccount) { self.account = account }

    public func authorize() async throws {
        throw MailProviderError.notImplemented("Gmail sign-in")
    }
    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        throw MailProviderError.notImplemented("Gmail sync")
    }
    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        throw MailProviderError.notImplemented("Gmail attachments")
    }
}
