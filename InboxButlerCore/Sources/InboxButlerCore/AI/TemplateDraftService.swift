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
        let lower = (message.subject + " " + body).lowercased()
        let asksSomething = body.contains("?")
        let core: String
        if (lower.contains("attached") || !message.attachments.isEmpty) && !asksSomething {
            core = "Thanks for sending this through. I've received it and will go over it shortly."
        } else if lower.contains("meeting") || lower.contains("catch up") || lower.contains("appointment") {
            core = "Thanks for getting in touch. Let me check my calendar and confirm a time shortly."
        } else if asksSomething {
            core = "Thanks for your email. Let me look into this and come back to you shortly with an answer."
        } else {
            core = "Thanks for letting me know. I'll take a look and be in touch if I need anything."
        }
        let text = "\(greeting)\n\n\(core)\n\n\(signOff)"
        return ReplyDraft(inReplyToMessageID: message.id, body: text, source: "basic")
    }

    public func summarize(_ message: MailMessage, body: String) async throws -> String { throw AIServiceError.notConfigured }
    public func scoreImportance(_ message: MailMessage, body: String) async throws -> Double { throw AIServiceError.notConfigured }
    public func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal] { throw AIServiceError.notConfigured }
}
