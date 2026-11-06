import Foundation

/// Crude HTML to plain text, for emails that have no text/plain part.
public enum HTMLText {
    public static func strip(_ html: String) -> String {
        var s = html
        for block in ["style", "script", "head"] {
            s = s.replacingOccurrences(of: "(?is)<\(block)[^>]*>.*?</\(block)>", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = GmailProvider.decodeEntities(s)
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
