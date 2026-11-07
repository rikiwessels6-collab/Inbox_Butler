import Foundation

/// A suggested reply. Lives only in the app until the user reviews it.
/// There is deliberately no "send" here: sending is a separate, explicit user
/// action that will be added later.
public struct ReplyDraft: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable { case suggested, edited, discarded }

    public let id: UUID
    public var inReplyToMessageID: String
    public var body: String
    public var status: Status
    public var createdAt: Date
    /// "on-device" (Apple Intelligence) or "basic" (template). Shown to the user.
    public var source: String

    public init(id: UUID = UUID(), inReplyToMessageID: String, body: String,
                status: Status = .suggested, createdAt: Date = Date(), source: String = "basic") {
        self.id = id
        self.inReplyToMessageID = inReplyToMessageID
        self.body = body
        self.status = status
        self.createdAt = createdAt
        self.source = source
    }
}
