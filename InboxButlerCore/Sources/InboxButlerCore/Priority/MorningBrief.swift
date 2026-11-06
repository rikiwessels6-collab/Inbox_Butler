import Foundation

/// Text for the optional 8am summary notification.
public enum MorningBrief {
    public static func text(priorityUnread: Int, needsReply: Int, eventsToday: Int) -> (title: String, body: String) {
        var parts: [String] = []
        if priorityUnread > 0 { parts.append("\(priorityUnread) priority email\(priorityUnread == 1 ? "" : "s")") }
        if needsReply > 0 { parts.append("\(needsReply) \(needsReply == 1 ? "reply" : "replies") waiting") }
        if eventsToday > 0 { parts.append("\(eventsToday) event\(eventsToday == 1 ? "" : "s") today") }
        return ("Good morning", parts.isEmpty ? "Nothing urgent. Enjoy your day." : parts.joined(separator: ", ") + ".")
    }
}
