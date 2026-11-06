import Foundation

public struct MailAddress: Hashable, Codable, Sendable {
    public var name: String?
    public var address: String
    public init(name: String? = nil, address: String) {
        self.name = name
        self.address = address
    }
    /// Name if known, otherwise the bare address.
    public var display: String { (name?.isEmpty == false ? name : nil) ?? address }
}

/// Attachment metadata only. Bytes are downloaded on demand via
/// `MailProvider.fetchAttachment`.
public struct AttachmentInfo: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case pdf, image, calendar, wordDocument, other }

    public let id: String          // provider attachment id
    public var filename: String
    public var mimeType: String
    public var byteCount: Int
    public var kind: Kind

    public init(id: String, filename: String, mimeType: String, byteCount: Int, kind: Kind) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.kind = kind
    }
}

/// Provider-independent message used by the whole app.
public struct MailMessage: Identifiable, Hashable, Codable, Sendable {
    public let accountID: UUID
    public let providerMessageID: String
    public var threadID: String?
    public var from: MailAddress
    public var to: [MailAddress]
    public var subject: String
    /// Short plain-text preview.
    public var snippet: String
    public var receivedAt: Date
    public var isRead: Bool
    public var attachments: [AttachmentInfo]
    /// 0...1, filled in by the AI layer. nil = not scored yet.
    public var importance: Double?
    /// True if the user still owes this sender a reply.
    public var awaitingReply: Bool

    /// Unique across accounts (provider ids alone can collide).
    public var id: String { "\(accountID.uuidString)/\(providerMessageID)" }

    public init(accountID: UUID, providerMessageID: String, threadID: String? = nil,
                from: MailAddress, to: [MailAddress] = [], subject: String, snippet: String,
                receivedAt: Date, isRead: Bool = false, attachments: [AttachmentInfo] = [],
                importance: Double? = nil, awaitingReply: Bool = false) {
        self.accountID = accountID
        self.providerMessageID = providerMessageID
        self.threadID = threadID
        self.from = from
        self.to = to
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.attachments = attachments
        self.importance = importance
        self.awaitingReply = awaitingReply
    }
}
