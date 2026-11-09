import Foundation

/// Cleans the one-line preview shown in the inbox: marketing mail starts with things like
/// "View in browser" and long tracking links, which push out the actual message.
public enum PreviewText {
    private static let boilerplate = [
        "view this email in your browser", "view in your browser", "view in browser", "view online",
        "view email in browser", "having trouble viewing this email", "click here to view",
        "if you can't see this email", "unsubscribe"
    ]

    public static func clean(_ text: String) -> String {
        // Invisible padding characters that marketing mail uses to pad previews.
        let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{034F}", "\u{00AD}", "\u{FEFF}"]
        var out = String(String.UnicodeScalarView(text.unicodeScalars.filter { !invisible.contains($0) }))
        out = out.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        for phrase in boilerplate {
            out = out.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|·•:;,"))
        return out.trimmingCharacters(in: trimSet)
    }

    /// A one-line gist for personal mail: drops the greeting ("Hi Sam,") and stops at the end of
    /// the first sentence. Extractive, so it is instant, offline and never invents anything.
    public static func gist(_ text: String, limit: Int = 140) -> String {
        var out = clean(text)
        if let comma = out.firstIndex(of: ","), out.distance(from: out.startIndex, to: comma) <= 24 {
            let lead = out[..<comma].lowercased()
            if ["hi", "hello", "hey", "dear", "good morning", "good afternoon", "good evening"].contains(where: { lead.hasPrefix($0) }) {
                out = String(out[out.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let end = out.firstIndex(where: { ".!?".contains($0) }), out.distance(from: out.startIndex, to: end) >= 12,
           out.distance(from: out.startIndex, to: end) < limit {
            out = String(out[...end])
        }
        if out.count > limit {
            let cut = String(out.prefix(limit))
            out = (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut) + "…"
        }
        if let first = out.first { out = first.uppercased() + out.dropFirst() }
        return out
    }
}
