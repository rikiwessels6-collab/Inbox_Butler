import Foundation

/// Fallback used when on-device AI isn't available: a reply built from what the email actually
/// says (its question, request, deadline and dates), in the user's greeting and sign-off.
/// They edit it before anything is sent.
public struct TemplateDraftService: AIService {
    public init() {}
    public var processingLocation: AIProcessingLocation { .onDevice }

    public func draftReply(to message: MailMessage, body: String, style: StyleProfile?) async throws -> ReplyDraft {
        let name = ReplyFormatter.firstName(message.from.display)
        let greeting = style?.greetings.first.map { $0.replacingOccurrences(of: "{name}", with: name) } ?? "Hi \(name),"
        let signOff = style?.signOffs.first ?? "Thanks,"
        let facts = ContentAwareDraft.facts(subject: message.subject, body: body, hasAttachment: !message.attachments.isEmpty)
        let core = ContentAwareDraft.reply(facts: facts)
        let text = "\(greeting)\n\n\(core)\n\n\(signOff)"
        return ReplyDraft(inReplyToMessageID: message.id, body: text, source: "basic")
    }

    public func summarize(_ message: MailMessage, body: String) async throws -> String { throw AIServiceError.notConfigured }
    public func scoreImportance(_ message: MailMessage, body: String) async throws -> Double { throw AIServiceError.notConfigured }
    public func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal] { throw AIServiceError.notConfigured }
}
