import Foundation

public enum RSVPAnswer: String, Sendable {
    case accept, tentative, decline

    /// The calendar standard's word for the answer.
    public var partStat: String {
        switch self {
        case .accept: return "ACCEPTED"
        case .tentative: return "TENTATIVE"
        case .decline: return "DECLINED"
        }
    }
}

/// Builds the calendar reply (an iCalendar METHOD:REPLY) for an invite, so answering YES / MAYBE / NO
/// updates the organiser's own calendar as well as sending a message. Pure text, no network.
public struct ICSReply: Equatable, Sendable {
    public let ics: String
    /// Where the reply should go (the invite's organiser), if the invite names one.
    public let organizer: String?
    public let summary: String?
}

public enum ICSReplyBuilder {
    public static func make(from inviteText: String, answer: RSVPAnswer, attendee: String, attendeeName: String? = nil,
                            now: Date = Date()) -> ICSReply? {
        var inEvent = false
        var done = false
        var uid: String?, sequence: String?, summary: String?
        var dtstart: String?, dtend: String?, organizerLine: String?, recurrence: String?
        for line in ICSParser.unfold(inviteText) where !done {
            guard let (name, _, value) = ICSParser.parseLine(line) else { continue }
            if name == "BEGIN", value.uppercased() == "VEVENT" { inEvent = true; continue }
            if name == "END", value.uppercased() == "VEVENT" { if inEvent { done = true }; continue }
            guard inEvent else { continue }
            switch name {
            case "UID": uid = value
            case "SEQUENCE": sequence = value
            case "SUMMARY": summary = value
            case "DTSTART": dtstart = line
            case "DTEND": dtend = line
            case "ORGANIZER": organizerLine = line
            case "RECURRENCE-ID": recurrence = line
            default: break
            }
        }
        guard let uid, !uid.isEmpty, let dtstart else { return nil }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        let cn = attendeeName.map { ";CN=\"\($0.replacingOccurrences(of: "\"", with: ""))\"" } ?? ""
        var lines = ["BEGIN:VCALENDAR", "PRODID:-//Boundary Line Apps//Inbox Butler//EN", "VERSION:2.0",
                     "CALSCALE:GREGORIAN", "METHOD:REPLY", "BEGIN:VEVENT",
                     "UID:\(uid)", "SEQUENCE:\(sequence ?? "0")", "DTSTAMP:\(stamp.string(from: now))", dtstart]
        if let dtend { lines.append(dtend) }
        if let recurrence { lines.append(recurrence) }
        if let summary { lines.append("SUMMARY:\(summary)") }
        if let organizerLine { lines.append(organizerLine) }
        lines.append("ATTENDEE;PARTSTAT=\(answer.partStat)\(cn):mailto:\(attendee)")
        lines += ["END:VEVENT", "END:VCALENDAR"]

        var organizer: String?
        if let organizerLine, let (_, _, value) = ICSParser.parseLine(organizerLine) {
            let v = value.trimmingCharacters(in: .whitespaces)
            organizer = v.lowercased().hasPrefix("mailto:") ? String(v.dropFirst(7)) : v
        }
        return ICSReply(ics: lines.joined(separator: "\r\n") + "\r\n", organizer: organizer, summary: summary)
    }
}
