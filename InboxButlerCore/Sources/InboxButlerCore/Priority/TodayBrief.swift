import Foundation

/// The "Today" card at the top of the inbox: what actually needs you, pulled together from the
/// calendar, events found in email, and mail that wants action. Pure logic, no UI, so it is tested.
public struct TodayBrief: Equatable, Sendable {
    public enum Kind: String, Sendable { case allDay, event, clash, suggestion, security, bill, reply }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let kind: Kind
        public let title: String
        public let detail: String
        /// The message to open when tapped, if the item came from one.
        public let messageID: String?
    }

    public let items: [Item]
    public var isEmpty: Bool { items.isEmpty }

    public static func make(messages: [MailMessage], events: [ExistingEvent], suggestions: [EventProposal],
                            now: Date = Date(), calendar: Calendar = .current) -> TodayBrief {
        var items: [Item] = []
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

        func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

        let today = events.filter { $0.start < dayEnd && $0.end > dayStart }
        for e in today.filter(\.isAllDay).prefix(2) {
            items.append(Item(id: "allday-\(e.id)", kind: .allDay, title: e.title, detail: "All day", messageID: nil))
        }

        let timed = today.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        for e in timed.prefix(3) {
            items.append(Item(id: "event-\(e.id)", kind: .event, title: e.title,
                              detail: "\(time(e.start)) · \(e.calendarTitle)", messageID: nil))
        }

        // Double-bookings stay visible (a clash is information, never a blocker).
        var clashes: [(ExistingEvent, ExistingEvent)] = []
        for i in timed.indices {
            for j in timed.indices where j > i && timed[i].start < timed[j].end && timed[j].start < timed[i].end {
                clashes.append((timed[i], timed[j]))
            }
        }
        if let first = clashes.first {
            let n = clashes.count
            items.append(Item(id: "clash", kind: .clash,
                              title: n == 1 ? "Two things overlap today" : "\(n) overlaps today",
                              detail: "\(first.0.title) and \(first.1.title) at \(time(max(first.0.start, first.1.start)))",
                              messageID: nil))
        }

        // Events found in email that you haven't added yet (today and tomorrow).
        let horizon = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayEnd
        for p in suggestions.filter({ $0.status == .proposed && $0.start >= dayStart && $0.start < horizon })
            .sorted(by: { $0.start < $1.start }).prefix(2) {
            let when = p.isAllDay ? "all day" : time(p.start)
            items.append(Item(id: "suggest-\(p.id)", kind: .suggestion, title: p.title,
                              detail: "Found in an email · \(when). Not in your calendar yet", messageID: p.sourceMessageID))
        }

        // Mail that wants action, newest first, each message used once.
        var used = Set<String>()
        let unread = messages.filter { !$0.isRead }.sorted { $0.receivedAt > $1.receivedAt }
        func take(_ kind: Kind, _ label: MessageLabel.Kind, limit: Int, detail: (MailMessage) -> String) {
            for m in unread where !used.contains(m.id) && MessageLabeler.labels(for: m, max: 9).contains(where: { $0.kind == label }) {
                if used.count >= 99 || items.filter({ $0.kind == kind }).count >= limit { break }
                used.insert(m.id)
                items.append(Item(id: "\(kind.rawValue)-\(m.id)", kind: kind, title: m.subject, detail: detail(m), messageID: m.id))
            }
        }
        take(.security, .security, limit: 2) { "\($0.from.display) · security" }
        take(.bill, .invoice, limit: 2) { "\($0.from.display) · bill" }

        let waiting = messages.filter { $0.awaitingReply && !used.contains($0.id) }.sorted { $0.receivedAt > $1.receivedAt }
        if let newest = waiting.first {
            let names = waiting.prefix(3).map { $0.from.display }.joined(separator: ", ")
            items.append(Item(id: "reply", kind: .reply,
                              title: waiting.count == 1 ? "1 person is waiting for a reply" : "\(waiting.count) people are waiting for a reply",
                              detail: names, messageID: newest.id))
        }
        return TodayBrief(items: items)
    }
}
