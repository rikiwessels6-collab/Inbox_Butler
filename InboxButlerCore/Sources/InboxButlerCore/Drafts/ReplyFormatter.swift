import Foundation

/// Small helpers for assembling a reply.
public enum ReplyFormatter {
    /// "Hello" -> "Re: Hello" (never "Re: Re: Hello").
    public static func subject(_ subject: String) -> String {
        let t = subject.trimmingCharacters(in: .whitespaces)
        return t.lowercased().hasPrefix("re:") ? t : "Re: " + t
    }

    /// "On 7 Nov 2026 at 9:00 am, Sam wrote:" followed by the original, each line quoted with "> ".
    public static func quoted(original body: String, sender: String, date: Date, maxLines: Int = 40) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxLines)
            .map { "> " + $0 }
        return "On \(f.string(from: date)), \(sender) wrote:\n" + lines.joined(separator: "\n")
    }

    /// "Sam Rivera" -> "Sam"; "sam.rivera@work.com" -> "Sam".
    public static func firstName(_ display: String) -> String {
        let base = display.contains("@") ? String(display.split(separator: "@")[0]) : display
        let first = base.split(whereSeparator: { " .,_-".contains($0) }).first.map(String.init) ?? base
        return first.prefix(1).uppercased() + first.dropFirst()
    }
}
