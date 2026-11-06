import Foundation

/// Finds likely events in plain text using Apple's on-device date detector.
/// No network and no AI model. It is a heuristic: it proposes, you confirm.
/// (The AI layer can refine titles later.)
public enum DateEventExtractor {
    public static let maxEvents = 8

    public static func events(in text: String, sourceMessageID: String,
                              source: EventProposal.Source = .messageText, fileLabel: String? = nil,
                              referenceDate: Date = Date()) -> [EventProposal] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let ns = text as NSString
        let horizon = referenceDate.addingTimeInterval(2 * 365 * 86_400)
        var out: [EventProposal] = []
        var seen = Set<String>()

        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard var date = match.date else { continue }
            var duration = match.duration
            let matched = ns.substring(with: match.range)

            // Deadline phrases ("due 26 Nov", "reply by Friday", "until 5pm Monday") come back
            // from the detector as a range that STARTS NOW and ends on the deadline.
            // The deadline is the end of that range, so use it as the date.
            if duration > 0 && Self.isDeadlinePhrase(matched, before: ns.substring(to: match.range.location)) {
                date = date.addingTimeInterval(duration)
                duration = 0
            }
            guard date >= referenceDate.addingTimeInterval(-3_600), date <= horizon else { continue }

            let hasTime = matched.range(of: #"\d{1,2}[:.]\d{2}|\b\d{1,2}\s?(am|pm)\b|\bnoon\b|\bmidnight\b"#,
                                        options: [.regularExpression, .caseInsensitive]) != nil
            let sentence = sentence(around: match.range, in: ns)
            let end: Date? = duration > 0 ? date.addingTimeInterval(duration) : nil
            let evidence = fileLabel.map { "\($0): \(sentence)" } ?? sentence

            let proposal = EventProposal(sourceMessageID: sourceMessageID, title: sentence, start: date, end: end,
                                         isAllDay: !hasTime, source: source, evidence: evidence)
            if seen.insert(proposal.fingerprint).inserted { out.append(proposal) }
            if out.count >= maxEvents { break }
        }
        return out
    }

    private static let deadlineWords = "(due|by|before|until|till|through|thru|deadline)"

    /// True if the matched text starts with, or is directly preceded by, a deadline word.
    static func isDeadlinePhrase(_ matched: String, before: String) -> Bool {
        let lead = matched.trimmingCharacters(in: .whitespaces).lowercased()
        if lead.range(of: "^\\(deadlineWords)\\b", options: .regularExpression) != nil { return true }
        let context = String(before.suffix(15)).lowercased()
        return context.range(of: "\\b\\(deadlineWords)[\\s:]*$", options: .regularExpression) != nil
    }

    /// The line containing the match, trimmed to a readable length.
    static func sentence(around range: NSRange, in text: NSString) -> String {
        let line = text.substring(with: text.lineRange(for: range)).trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard collapsed.count > 90 else { return collapsed }
        // Long line: keep ~90 characters around the date.
        let local = text.substring(with: range)
        guard let r = collapsed.range(of: local) else { return String(collapsed.prefix(90)) + "…" }
        let startOffset = max(0, collapsed.distance(from: collapsed.startIndex, to: r.lowerBound) - 40)
        let s = collapsed.index(collapsed.startIndex, offsetBy: startOffset)
        let e = collapsed.index(s, offsetBy: min(90, collapsed.distance(from: s, to: collapsed.endIndex)))
        var result = String(collapsed[s..<e])
        if startOffset > 0 { result = "…" + result }
        if e < collapsed.endIndex { result += "…" }
        return result
    }
}
