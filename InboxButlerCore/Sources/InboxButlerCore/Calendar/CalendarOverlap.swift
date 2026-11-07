import Foundation

public struct CalendarOverlap: Sendable {
    /// An event that looks like the same one (same title and start): probably already added.
    public var duplicate: ExistingEvent?
    /// Different events happening at the same time. Informational only.
    public var overlaps: [ExistingEvent]

    public static let none = CalendarOverlap(duplicate: nil, overlaps: [])
}

/// Pure logic for the "already there?" and "overlaps with..." hints.
public enum CalendarOverlapChecker {
    public static func classify(_ proposal: EventProposal, existing: [ExistingEvent]) -> CalendarOverlap {
        func normal(_ s: String) -> String {
            s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let wanted = normal(proposal.title)
        let duplicate = existing.first {
            normal($0.title) == wanted && $0.isAllDay == proposal.isAllDay
                && abs($0.start.timeIntervalSince(proposal.start)) < 120
        }

        let cal = Calendar.current
        let start = proposal.start
        let end: Date
        if proposal.isAllDay {
            end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start)) ?? start.addingTimeInterval(86_400)
        } else {
            end = proposal.end ?? start.addingTimeInterval(3_600)
        }
        let overlaps = existing.filter { e in
            if e == duplicate { return false }
            // All-day items (holidays, birthdays) would overlap everything on a timed event.
            if e.isAllDay && !proposal.isAllDay { return false }
            return e.start < end && e.end > start
        }
        return CalendarOverlap(duplicate: duplicate, overlaps: Array(overlaps.prefix(5)))
    }
}
