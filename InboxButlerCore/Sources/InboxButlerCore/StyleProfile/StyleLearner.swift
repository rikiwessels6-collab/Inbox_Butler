import Foundation

/// Learns how the user writes from their sent mail, entirely on the device.
/// It records habits (greeting, sign-off, length, tone, a few example replies).
public enum StyleLearner {
    private static let greetingPattern = #"^(hi|hello|hey|dear|good (morning|afternoon|evening)|morning)\b"#
    private static let signOffPattern = #"^(thanks|thank you|many thanks|cheers|regards|kind regards|best regards|best wishes|best|warm regards|sincerely|yours sincerely|ta|take care)[,!.]*$"#

    public static func learn(from bodies: [String], now: Date = Date()) -> StyleProfile {
        let texts = bodies.map(ownText).filter { !$0.isEmpty }
        var greetings: [String: Int] = [:]
        var signOffs: [String: Int] = [:]
        var sentenceWords: [Int] = []
        var formal = 0, casual = 0
        var emoji = false
        var trigrams: [String: Int] = [:]

        for text in texts {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = lines.first, first.count <= 40, first.range(of: greetingPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                greetings[normalizeGreeting(first), default: 0] += 1
            }
            if let signOff = lines.suffix(6).last(where: { $0.range(of: signOffPattern, options: [.regularExpression, .caseInsensitive]) != nil }) {
                signOffs[signOff, default: 0] += 1
            }

            let lower = text.lowercased()
            for marker in ["regards", "dear ", "sincerely", "please find", "kindly", "i hope this email"] where lower.contains(marker) { formal += 1 }
            for marker in ["hey", "cheers", "lol", "haha", "thanks!", "no worries"] where lower.contains(marker) { casual += 1 }
            casual += lower.components(separatedBy: "'").count - 1 > 1 ? 1 : 0   // contractions
            if text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { emoji = true }

            for sentence in text.split(whereSeparator: { ".!?\n".contains($0) }) {
                let n = sentence.split(whereSeparator: \.isWhitespace).count
                if n > 0 { sentenceWords.append(n) }
            }

            let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
            if words.count >= 3 {
                for i in 0..<(words.count - 2) { trigrams[words[i...(i + 2)].joined(separator: " "), default: 0] += 1 }
            }
        }

        func top(_ d: [String: Int], _ n: Int) -> [String] {
            d.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(n).map(\.key)
        }
        let minRepeat = texts.count >= 10 ? 3 : 2
        let phrases = top(trigrams.filter { $0.value >= minRepeat }, 5)
        let avg = sentenceWords.isEmpty ? 0 : Double(sentenceWords.reduce(0, +)) / Double(sentenceWords.count)
        let hits = formal + casual
        let formality = hits == 0 ? 0.5 : min(1, max(0, 0.5 + Double(formal - casual) / Double(hits) * 0.4))
        let examples = texts.filter { $0.count >= 40 && $0.count <= 600 }.prefix(3).map { String($0.prefix(500)) }

        return StyleProfile(greetings: top(greetings, 3), signOffs: top(signOffs, 3), averageSentenceWords: avg,
                            formality: formality, usesEmoji: emoji, commonPhrases: phrases,
                            sampleCount: texts.count, exampleReplies: Array(examples), updatedAt: now)
    }

    /// The part the user actually wrote: drops quoted replies ("> ..." and "On ... wrote:").
    static func ownText(_ body: String) -> String {
        var kept: [String] = []
        for line in body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">") { continue }
            if t.range(of: #"^on .+ wrote:?$"#, options: [.regularExpression, .caseInsensitive]) != nil { break }
            if t.hasPrefix("-----Original Message") || t.hasPrefix("From:") && !kept.isEmpty { break }
            kept.append(String(line))
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Hi Sam," -> "Hi {name},"
    static func normalizeGreeting(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(hi|hello|hey|dear)\s+[^,!\n]+([,!]?)$"#, with: "$1 {name}$2",
                                  options: [.regularExpression, .caseInsensitive])
    }
}
