import Foundation

/// An event found in an email or attachment. It is only a PROPOSAL: nothing is
/// added to the calendar until the user confirms it.
public struct EventProposal: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable { case proposed, confirmed, dismissed }

    public let id: UUID
    public var sourceMessageID: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var status: Status

    public init(id: UUID = UUID(), sourceMessageID: String, title: String, start: Date,
                end: Date? = nil, isAllDay: Bool = false, location: String? = nil,
                notes: String? = nil, status: Status = .proposed) {
        self.id = id
        self.sourceMessageID = sourceMessageID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.status = status
    }
}

/// Writes a confirmed proposal to the calendar (EventKit implementation comes
/// with the Calendar module). Callers must only invoke it after the user taps
/// "Add" on that specific proposal.
public protocol CalendarWriter: Sendable {
    func add(_ proposal: EventProposal) async throws
}
