import Foundation

/// Fallback used when on-device AI isn't available: a simple, honest holding reply in the
/// user's greeting and sign-off. They edit it before anything is sent.
public struct TemplateDraftService: AIService {
    public init() {}
    public var processingLocation: AIProcessingLocation { .onDevice }

    public func draftReply(to message: MailMessage, body: String, style: StyleProfile?) async throws -> ReplyDraft {
        let name = ReplyFormatter.firstName(message.from.display)
        let greeting = style?.greetings.first.map { $0.replacingOccurrences(of: "{name}", with: name) } ?? "Hi \(name),"
        let signOff = style?.signOffs.first ?? "Thanks,"
        let text = "\(greeting)\n\nThanks for your email. I'll look into this and get back to you shortly.\n\n\(signOff)"
        return ReplyDraft(inReplyToMessageID: message.id, body: text, source: "basic")
    }

    public func summarize(_ message: MailMessage, body: String) async throws -> String { throw AIServiceError.notConfigured }
    public func scoreImportance(_ message: MailMessage, body: String) async throws -> Double { throw AIServiceError.notConfigured }
    public func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal] { throw AIServiceError.notConfigured }
}
