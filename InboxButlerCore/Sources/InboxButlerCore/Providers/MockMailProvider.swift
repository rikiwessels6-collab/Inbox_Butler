import Foundation

/// Working in-memory provider used by the app shell, previews and tests.
public struct MockMailProvider: MailProvider {
    public let account: MailAccount
    private let messages: [MailMessage]

    public init(account: MailAccount, messages: [MailMessage]) {
        self.account = account
        self.messages = messages
    }

    public func authorize() async throws {}

    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        guard mailbox == .inbox else { return MailPage(messages: []) }
        let sorted = messages.sorted { $0.receivedAt > $1.receivedAt }
        return MailPage(messages: Array(sorted.prefix(limit)), nextCursor: SyncCursor("mock"))
    }

    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        Data()
    }
}
