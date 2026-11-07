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

/// Adds confirmed events to the calendar the user chooses.
///
/// PRIVACY: this needs FULL calendar access (iOS gives no way to list calendars with
/// write-only access). The app uses it for exactly two things: listing your writable
/// calendars, and looking at events around the time of an event you are about to add,
/// to show overlaps. Nothing from your calendar is stored or sent anywhere.
///
/// Google calendars appear here when the Google account is added in iOS
/// Settings > Calendar > Accounts. Events written to them sync back to Google.
public actor EventKitCalendarWriter: CalendarWriter {
    private let store = EKEventStore()

    public init() {}

    public func accessState() async -> CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return .granted }
        if status == .denied || status == .restricted { return .denied }
        return .notDetermined   // includes write-only from an older build: ask again for full
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() async throws -> [CalendarInfo] {
        guard await accessState() == .granted else { throw CalendarError.accessDenied }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func nearbyEvents(for proposal: EventProposal) async -> [ExistingEvent] {
        guard await accessState() == .granted else { return [] }
        let cal = Calendar.current
        let start: Date, end: Date
        if proposal.isAllDay {
            start = cal.startOfDay(for: proposal.start)
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        } else {
            start = proposal.start.addingTimeInterval(-60)
            end = (proposal.end ?? proposal.start.addingTimeInterval(3_600)).addingTimeInterval(60)
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).prefix(30).map {
            ExistingEvent(title: $0.title ?? "", calendarTitle: $0.calendar?.title ?? "",
                          start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
    }

    public func add(_ proposal: EventProposal, toCalendar calendarID: String?) async throws {
        if await accessState() != .granted {
            guard await requestAccess() else { throw CalendarError.accessDenied }
        }
        let chosen = calendarID.flatMap { store.calendar(withIdentifier: $0) }
        guard let calendar = (chosen?.allowsContentModifications == true ? chosen : nil)
                ?? store.defaultCalendarForNewEvents else { throw CalendarError.noDefaultCalendar }

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
