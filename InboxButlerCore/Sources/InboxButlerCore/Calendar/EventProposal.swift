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

/// Writes a confirmed proposal to the calendar. Callers must only invoke it after
/// the user taps "Add" on that specific proposal.
public protocol CalendarWriter: Sendable {
    func add(_ proposal: EventProposal) async throws
}
