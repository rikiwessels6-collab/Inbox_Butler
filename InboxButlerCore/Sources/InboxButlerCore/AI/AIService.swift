import Foundation

/// Where an AI request is processed. Surfaced in the UI so it is always clear
/// whether mail text leaves the device.
public enum AIProcessingLocation: String, Codable, Sendable {
    case onDevice          // Apple Foundation Models: nothing leaves the device
    case backendProxy      // text is sent to the user's own proxy server
    case cloud             // OPT-IN: the email being replied to goes to Anthropic's API, using the user's own key
    case unconfigured      // no AI layer chosen yet
}

public enum AIServiceError: Error, LocalizedError, Sendable {
    case notConfigured
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "This AI feature isn't available."
        case .unavailable(let why): return why
        }
    }
}

/// The AI layer. DECISION PENDING: on-device Foundation Models vs. backend proxy
/// (see ARCHITECTURE.md, open question 1). Either way:
///  - no API key is ever built into the app (a person's OWN key, if they choose cloud drafts, lives only in their Keychain);
///  - drafts are returned for review and are never sent automatically.
public protocol AIService: Sendable {
    var processingLocation: AIProcessingLocation { get }

    func summarize(_ message: MailMessage, body: String) async throws -> String
    /// 0...1, higher = more urgent/important.
    func scoreImportance(_ message: MailMessage, body: String) async throws -> Double
    func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal]
    func draftReply(to message: MailMessage, body: String, style: StyleProfile?) async throws -> ReplyDraft
}

/// Placeholder until the AI layer is chosen. Every call throws `.notConfigured`.
public struct UnconfiguredAIService: AIService {
    public init() {}
    public var processingLocation: AIProcessingLocation { .unconfigured }

    public func summarize(_ message: MailMessage, body: String) async throws -> String {
        throw AIServiceError.notConfigured
    }
    public func scoreImportance(_ message: MailMessage, body: String) async throws -> Double {
        throw AIServiceError.notConfigured
    }
    public func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal] {
        throw AIServiceError.notConfigured
    }
    public func draftReply(to message: MailMessage, body: String, style: StyleProfile?) async throws -> ReplyDraft {
        throw AIServiceError.notConfigured
    }
}
