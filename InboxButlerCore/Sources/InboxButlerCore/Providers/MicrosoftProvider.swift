import Foundation

/// STUB. Planned: Microsoft Graph (Mail.Read, offline_access), MSAL-style OAuth + PKCE.
/// Tokens/passwords go to `KeychainStore` only. Read-only access.
public struct MicrosoftProvider: MailProvider {
    public let account: MailAccount
    public init(account: MailAccount) { self.account = account }

    public func authorize() async throws {
        throw MailProviderError.notImplemented("Microsoft sign-in")
    }
    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        throw MailProviderError.notImplemented("Microsoft sync")
    }
    public func fetchBody(for message: MailMessage) async throws -> String {
        throw MailProviderError.notImplemented("Microsoft message body")
    }
    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        throw MailProviderError.notImplemented("Microsoft attachments")
    }
}
