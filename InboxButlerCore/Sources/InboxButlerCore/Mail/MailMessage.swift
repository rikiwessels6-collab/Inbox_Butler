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

    /// Tiny inline pictures (logos, signatures, "image.png") that are part of the layout, not
    /// something the sender meant you to open. Hidden from attachment lists.
    public var isLikelyInline: Bool {
        guard kind == .image, byteCount < 30_000 else { return false }
        let name = filename.lowercased()
        return name.isEmpty || ["image", "img", "logo", "outlook-", "ii_", "unnamed", "signature", "spacer"].contains { name.hasPrefix($0) }
    }
}

/// A label the user made in their mail account (a Gmail label), shown as a coloured chip.
public struct MailLabelTag: Hashable, Codable, Sendable {
    public var name: String
    /// 0xRRGGBB from the account's own label colour, if it has one.
    public var colorHex: UInt32?
    public init(name: String, colorHex: UInt32? = nil) { self.name = name; self.colorHex = colorHex }
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
    /// Newsletter / mailing list / automated sender.
    public var isBulk: Bool
    /// The user's own labels from the account (Gmail), for display.
    public var labels: [MailLabelTag]

    /// Unique across accounts (provider ids alone can collide).
    public var id: String { "\(accountID.uuidString)/\(providerMessageID)" }

    public init(accountID: UUID, providerMessageID: String, threadID: String? = nil,
                from: MailAddress, to: [MailAddress] = [], subject: String, snippet: String,
                receivedAt: Date, isRead: Bool = false, attachments: [AttachmentInfo] = [],
                importance: Double? = nil, awaitingReply: Bool = false, isBulk: Bool = false,
                labels: [MailLabelTag] = []) {
        self.accountID = accountID
        self.providerMessageID = providerMessageID
        self.threadID = threadID
        self.from = from
        self.to = to
        self.subject = subject
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.attachments = attachments.filter { !$0.isLikelyInline }
        self.importance = importance
        self.awaitingReply = awaitingReply
        self.isBulk = isBulk
        self.labels = labels
    }
}
