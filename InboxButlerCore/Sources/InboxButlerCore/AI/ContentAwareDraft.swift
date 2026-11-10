import Foundation

/// Builds a reply that responds to what the email actually says, without any AI model: it finds
/// the question or request, any deadline, and the dates mentioned. It never invents an answer;
/// where only the user can answer, it leaves a clear [placeholder] for them to fill in.
public enum ContentAwareDraft {
    public struct Facts: Equatable, Sendable {
        public var topic: String
        public var question: String?
        public var request: String?
        public var deadline: String?
        public var dates: [String]
        public var hasAttachment: Bool
    }

    // MARK: Reading the email

    public static func facts(subject: String, body: String, hasAttachment: Bool) -> Facts {
        let topic = cleanSubject(subject)
        let sentences = splitSentences(body)
        let question = sentences.first { $0.contains("?") && $0.count >= 12 }
        let request = sentences.first { s in
            let l = s.lowercased()
            return requestCues.contains { l.contains($0) } && !s.contains("?")
        }
        let deadline = (request ?? question).flatMap { firstMatch(deadlinePattern, in: $0, group: 1) }
        var dates: [String] = []
        for m in allMatches(datePattern, in: body) where !dates.contains(where: { $0.caseInsensitiveCompare(m) == .orderedSame }) {
            dates.append(m)
            if dates.count == 2 { break }
        }
        let lower = body.lowercased()
        return Facts(topic: topic, question: question.map(trim), request: request.map(trim), deadline: deadline,
                     dates: dates, hasAttachment: hasAttachment || lower.contains("attached") || lower.contains("attachment"))
    }

    // MARK: Writing the reply

    public static func reply(facts f: Facts) -> String {
        let topic = f.topic.isEmpty ? "your email" : f.topic
        if let q = f.question {
            return "Thanks for your email about \(topic). On your question (\"\(shorten(q, 90))\"): [add your answer here]."
        }
        if f.request != nil {
            let by = f.deadline.map { " by \($0)" } ?? ""
            return "Thanks for your email about \(topic). I'll take care of this\(by) and let you know once it's done."
        }
        if f.hasAttachment {
            let noted = f.dates.isEmpty ? "I'll go through the details" : "I've noted the dates (\(f.dates.joined(separator: ", ")))"
            return "Thanks for sending through \(topic). \(noted)."
        }
        if !f.dates.isEmpty {
            return "Thanks for letting me know about \(topic). I've noted \(f.dates.joined(separator: " and "))."
        }
        return "Thanks for letting me know about \(topic)."
    }

    // MARK: Helpers

    private static let requestCues = [
        "please ", "could you", "can you", "would you", "kindly", "need you to", "you must", "required to",
        "return the", "submit", "complete the", "sign and", "rsvp", "let us know", "let me know", "reply by",
        "respond by", "confirm "
    ]

    private static let day = "(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    private static let month = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*"
    private static let deadlinePattern =
        "(?i)\\b(?:by|before|until|no later than)\\s+((?:next\\s+)?\(day)(?:\\s+week\\s*\\d+)?|\\d{1,2}(?:st|nd|rd|th)?\\s+\(month)|\(month)\\s+\\d{1,2}(?:st|nd|rd|th)?|tomorrow|end of (?:the )?(?:week|month|day))"
    private static let datePattern =
        "(?i)\\b\(day)(?:\\s+week\\s*\\d+)?|\\b\\d{1,2}(?:st|nd|rd|th)?\\s+\(month)"

    static func cleanSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        while let r = s.range(of: "^(re|fwd|fw)\\s*:\\s*", options: [.regularExpression, .caseInsensitive]) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitSentences(_ body: String) -> [String] {
        // Keep the "?" on questions so they can be recognised; drop other sentence endings.
        var out: [String] = []
        var current = ""
        for ch in body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) {
            if ch == "?" { current.append(ch); out.append(current); current = "" }
            else if ch == "." || ch == "!" { out.append(current); current = "" }
            else { current.append(ch) }
        }
        if !current.isEmpty { out.append(current) }
        return out.map(trim).filter { $0.count >= 8 }
    }

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:"))) }

    private static func shorten(_ s: String, _ limit: Int) -> String {
        guard s.count > limit else { return s }
        let cut = String(s.prefix(limit))
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut) + "…"
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}
