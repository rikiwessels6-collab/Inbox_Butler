import Foundation
import EventKit

public enum CalendarError: Error, LocalizedError, Sendable {
    case accessDenied
    case noDefaultCalendar
    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "Calendar access is off. Allow it in Settings > Inbox Butler > Calendars."
        case .noDefaultCalendar: return "No default calendar is set on this device."
        }
    }
}

/// Adds confirmed events to the user's default calendar.
///
/// PRIVACY: uses iOS's WRITE-ONLY calendar access. The app can add events but
/// cannot read, list or change any existing calendar entry.
public actor EventKitCalendarWriter: CalendarWriter {
    private let store = EKEventStore()

    public init() {}

    public func add(_ proposal: EventProposal) async throws {
        guard try await store.requestWriteOnlyAccessToEvents() else { throw CalendarError.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noDefaultCalendar }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = proposal.title
        event.startDate = proposal.start
        event.isAllDay = proposal.isAllDay
        // All-day events end on their (inclusive) last day; timed events default to one hour.
        event.endDate = proposal.end ?? (proposal.isAllDay ? proposal.start : proposal.start.addingTimeInterval(3_600))
        if event.endDate < event.startDate { event.endDate = event.startDate.addingTimeInterval(3_600) }
        event.location = proposal.location
        event.notes = [proposal.notes, "Added by Inbox Butler. " + (proposal.evidence ?? "")]
            .compactMap { $0 }.joined(separator: "\n\n")
        try store.save(event, span: .thisEvent, commit: true)
    }
}
