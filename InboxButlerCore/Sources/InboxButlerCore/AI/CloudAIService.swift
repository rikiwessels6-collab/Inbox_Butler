import Foundation

/// The Claude models offered for cloud drafts, with what they cost, so the person chooses.
public enum CloudModel: String, CaseIterable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    public var title: String {
        switch self {
        case .opus: return "Claude Opus 5.5"
        case .sonnet: return "Claude Sonnet 5.5"
        case .haiku: return "Claude Haiku 5.5"
        }
    }

    /// Rough cost of one draft (about 1,500 words in, a short reply out).
    public var costHint: String {
        switch self {
        case .opus: return "Best writing. About 1 cent per draft."
        case .sonnet: return "Great writing. About half a cent per draft."
        case .haiku: return "Fast and very cheap. Well under a tenth of a cent per draft."
        }
    }
}

/// OPTIONAL cloud drafting for phones without Apple Intelligence. Sends only the one email being
/// replied to, plus a short summary of the user's writing style, to Anthropic's API over HTTPS.
/// It runs only when the person has switched it on and added their OWN API key (kept in the
/// iOS Keychain, never shipped in the app). The reply is returned for review and never sent.
public struct CloudAIService: AIService {
    public static let keychainKey = "anthropic.apiKey"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    private let apiKey: String
    private let model: CloudModel
    private let transport: HTTPTransport

    public init(apiKey: String, model: CloudModel = .opus, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
    }

    public var processingLocation: AIProcessingLocation { .cloud }

    public func draftReply(to message: MailMessage, body: String, style: StyleProfile?) async throws -> ReplyDraft {
        let prompt = DraftPrompt.make(message: message, body: body, style: style)
        // Opus and Sonnet can hand a declined request to a fallback model server-side; if the API
        // rejects that option for any reason, try once more without it.
        let wantsFallback = model != .haiku
        var (data, status) = try await send(prompt, withFallback: wantsFallback)
        if status == 400, wantsFallback { (data, status) = try await send(prompt, withFallback: false) }
        let text = try Self.parseReply(data: data, status: status)
        return ReplyDraft(inReplyToMessageID: message.id, body: text, source: "cloud")
    }

    public func summarize(_ message: MailMessage, body: String) async throws -> String { throw AIServiceError.notConfigured }
    public func scoreImportance(_ message: MailMessage, body: String) async throws -> Double { throw AIServiceError.notConfigured }
    public func extractEvents(from text: String, referenceDate: Date) async throws -> [EventProposal] { throw AIServiceError.notConfigured }

    // MARK: Request and response

    private func send(_ prompt: DraftPrompt.Output, withFallback: Bool) async throws -> (Data, Int) {
        let request = Self.makeRequest(apiKey: apiKey, model: model, prompt: prompt, withFallback: withFallback)
        let (data, http) = try await transport.send(request)
        return (data, http.statusCode)
    }

    static func makeRequest(apiKey: String, model: CloudModel, prompt: DraftPrompt.Output, withFallback: Bool) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2048,                       // thinking tokens share this budget
            "system": prompt.instructions,
            "messages": [["role": "user", "content": prompt.prompt]],
            "output_config": ["effort": "low"]        // a short reply needs little reasoning
        ]
        if withFallback {
            request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseReply(data: Data, status: Int) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            let detail = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            switch status {
            case 401, 403: throw AIServiceError.unavailable("Anthropic rejected the API key. Check it in Settings.")
            case 429: throw AIServiceError.unavailable("Anthropic says too many requests right now. Try again in a minute.")
            case 402: throw AIServiceError.unavailable("Your Anthropic account needs credit. Add some at console.anthropic.com.")
            default: throw AIServiceError.unavailable("Claude couldn't write this one (error \(status)). \(detail)")
            }
        }
        if (json?["stop_reason"] as? String) == "refusal" {
            throw AIServiceError.unavailable("Claude declined to write a reply to this email.")
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIServiceError.unavailable("Claude returned an empty draft.") }
        return text
    }
}
