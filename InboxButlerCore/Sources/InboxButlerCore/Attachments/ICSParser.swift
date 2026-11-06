import Foundation

/// Reads iCalendar (.ics) invites. Recurrence rules are ignored (only the first
/// occurrence is proposed). Cancelled events are skipped.
public enum ICSParser {
    public static func events(from text: String, sourceMessageID: String,
                              referenceDate: Date = Date(), filename: String? = nil) -> [EventProposal] {
        let lines = unfold(text)
        var results: [EventProposal] = []
        var current: [(name: String, params: [String: String], value: String)]? = nil
        var methodCancel = false

        for line in lines {
            guard let (name, params, value) = parseLine(line) else { continue }
            switch (name, value.uppercased()) {
            case ("METHOD", "CANCEL"): methodCancel = true
            case ("BEGIN", "VEVENT"): current = []
            case ("END", "VEVENT"):
                if let props = current, !methodCancel,
                   let proposal = makeProposal(props, sourceMessageID: sourceMessageID, filename: filename),
                   proposal.start >= referenceDate.addingTimeInterval(-86_400) {
                    results.append(proposal)
                }
                current = nil
            default:
                current?.append((name, params, value))
            }
        }
        return results
    }

    // MARK: Internals

    /// RFC 5545 line folding: a line starting with space/tab continues the previous one.
    static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !out.isEmpty {
                out[out.count - 1] += raw.dropFirst()
            } else {
                out.append(String(raw))
            }
        }
        return out
    }

    /// "DTSTART;TZID=Europe/London:20261115T140000" -> ("DTSTART", ["TZID": "Europe/London"], "20261115T140000")
    static func parseLine(_ line: String) -> (String, [String: String], String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].split(separator: ";").map(String.init)
        guard let name = head.first?.uppercased() else { return nil }
        var params: [String: String] = [:]
        for p in head.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
        }
        return (name, params, String(line[line.index(after: colon)...]))
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Returns (date, isAllDay).
    static func parseDate(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if params["VALUE"] == "DATE" || (value.count == 8 && !value.contains("T")) {
            f.dateFormat = "yyyyMMdd"
            f.timeZone = .current
            return f.date(from: value).map { ($0, true) }
        }
        if value.hasSuffix("Z") {
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
        } else {
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            // TZID if known; otherwise "floating" time = the device's time zone.
            f.timeZone = params["TZID"].flatMap { TimeZone(identifier: $0) } ?? .current
        }
        return f.date(from: value).map { ($0, false) }
    }

    private static func makeProposal(_ props: [(name: String, params: [String: String], value: String)],
                                     sourceMessageID: String, filename: String?) -> EventProposal? {
        func first(_ name: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == name }.map { ($0.params, $0.value) }
        }
        if first("STATUS")?.value.uppercased() == "CANCELLED" { return nil }
        guard let startProp = first("DTSTART"), let (start, allDay) = parseDate(startProp.value, params: startProp.params) else { return nil }
        var end: Date?
        if let endProp = first("DTEND") { end = parseDate(endProp.value, params: endProp.params)?.0 }
        // iCalendar all-day DTEND is exclusive (the day after): step back so it reads correctly.
        if allDay, let e = end { end = Calendar.current.date(byAdding: .day, value: -1, to: e) }
        let title = first("SUMMARY").map { unescape($0.value) } ?? "Event"
        return EventProposal(sourceMessageID: sourceMessageID, title: title, start: start, end: end, isAllDay: allDay,
                             location: first("LOCATION").map { unescape($0.value) },
                             notes: first("DESCRIPTION").map { unescape($0.value) },
                             source: .calendarFile, evidence: filename.map { "Calendar file: \($0)" } ?? "Calendar file")
    }
}
