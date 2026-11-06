import Foundation

/// Working in-memory provider used by the app shell, previews and tests.
public struct MockMailProvider: MailProvider {
    public let account: MailAccount
    private let messages: [MailMessage]
    private let bodies: [String: String]          // providerMessageID -> body text
    private let attachmentData: [String: Data]    // attachment id -> bytes
    private let htmlBodies: [String: String]      // providerMessageID -> HTML

    public init(account: MailAccount, messages: [MailMessage],
                bodies: [String: String] = [:], attachmentData: [String: Data] = [:],
                htmlBodies: [String: String] = [:]) {
        self.account = account
        self.messages = messages
        self.bodies = bodies
        self.attachmentData = attachmentData
        self.htmlBodies = htmlBodies
    }

    public func authorize() async throws {}

    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        guard mailbox == .inbox else { return MailPage(messages: []) }
        let sorted = messages.sorted { $0.receivedAt > $1.receivedAt }
        return MailPage(messages: Array(sorted.prefix(limit)), nextCursor: SyncCursor("mock"))
    }

    public func fetchBody(for message: MailMessage) async throws -> String {
        bodies[message.providerMessageID] ?? message.snippet
    }

    public func fetchHTMLBody(for message: MailMessage) async throws -> String? {
        htmlBodies[message.providerMessageID]
    }

    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        attachmentData[attachment.id] ?? Data()
    }
}
