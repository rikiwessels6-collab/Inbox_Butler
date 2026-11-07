import Foundation

/// An event found in an email or attachment. It is only a PROPOSAL: nothing is
/// added to the calendar until the user confirms it.
public struct EventProposal: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable { case proposed, confirmed, dismissed }
    /// Where the event was found, so the UI can show its evidence.
    public enum Source: String, Codable, Sendable { case calendarFile, messageText, attachmentText }

    public let id: UUID
    public var sourceMessageID: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var status: Status
    public var source: Source
    /// The sentence or file the event was read from (shown to the user).
    public var evidence: String?

    public init(id: UUID = UUID(), sourceMessageID: String, title: String, start: Date,
                end: Date? = nil, isAllDay: Bool = false, location: String? = nil,
                notes: String? = nil, status: Status = .proposed,
                source: Source = .messageText, evidence: String? = nil) {
        self.id = id
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.status = status
        self.source = source
        self.evidence = evidence
    }

    /// Stable identity across re-scans (ids are random each time). Used so a
    /// dismissed or added event never comes back. Based on message + start time
    /// (not the title, which the user can edit).
    public var fingerprint: String {
        "\(sourceMessageID)|\(Int(start.timeIntervalSince1970))|\(isAllDay ? "d" : "t")"
    }
}

public enum CalendarAccess: Sendable { case notDetermined, granted, denied }

/// A calendar the user can add events to (iCloud, Google, shared family calendars...).
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String   // "iCloud", "Gmail", ...

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id; self.title = title; self.sourceTitle = sourceTitle
    }

    /// "iCloud · Family", or just the title when the source adds nothing.
    public var displayName: String {
        sourceTitle.isEmpty || sourceTitle == title ? title : "\(sourceTitle) · \(title)"
    }
}

/// An event already in the calendar, read ONLY to show overlaps for an event being added.
/// It is never stored or sent anywhere.
public struct ExistingEvent: Hashable, Sendable {
    public let title: String
    public let calendarTitle: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String, calendarTitle: String, start: Date, end: Date, isAllDay: Bool) {
        self.title = title; self.calendarTitle = calendarTitle
        self.start = start; self.end = end; self.isAllDay = isAllDay
    }
}

/// Writes a confirmed proposal to the calendar. Callers must only invoke it after
/// the user taps "Add" on that specific proposal. Clashes with other events NEVER
/// prevent an add (families have overlapping calendars).
public protocol CalendarWriter: Sendable {
    func accessState() async -> CalendarAccess
    func requestAccess() async -> Bool
    func calendars() async throws -> [CalendarInfo]
    /// Events around the proposal's time, for the informational overlap display.
    func nearbyEvents(for proposal: EventProposal) async -> [ExistingEvent]
    func add(_ proposal: EventProposal, toCalendar calendarID: String?) async throws
}
