import Foundation

/// Everything the widget shows, precomputed by the app. The widget never reads
/// mail, tokens or the database; only this small file.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct EmailItem: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var sender: String
        public var subject: String
        public var accountLabel: String
        public init(id: String, sender: String, subject: String, accountLabel: String) {
            self.id = id; self.sender = sender; self.subject = subject; self.accountLabel = accountLabel
        }
    }
    public struct EventItem: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var start: Date
        public init(id: String, title: String, start: Date) {
            self.id = id; self.title = title; self.start = start
        }
    }

    public var urgentEmails: [EmailItem]
    public var todaysEvents: [EventItem]
    public var repliesWaiting: Int
    public var generatedAt: Date

    public init(urgentEmails: [EmailItem] = [], todaysEvents: [EventItem] = [],
                repliesWaiting: Int = 0, generatedAt: Date = Date()) {
        self.urgentEmails = urgentEmails
        self.todaysEvents = todaysEvents
        self.repliesWaiting = repliesWaiting
        self.generatedAt = generatedAt
    }

    public static let placeholder = WidgetSnapshot(
        urgentEmails: [.init(id: "1", sender: "Sam", subject: "Contract needs signing", accountLabel: "Work")],
        todaysEvents: [.init(id: "1", title: "Dentist", start: Date())],
        repliesWaiting: 2)
}

extension WidgetSnapshot {
    /// Builds the widget content from the current inbox.
    /// - Urgent: unread, importance >= 0.7, most important first (max 5).
    /// - Events: non-dismissed proposals/confirmed events starting today.
    /// - Replies waiting: messages flagged `awaitingReply`.
    public static func make(messages: [MailMessage], accounts: [MailAccount],
                            events: [EventProposal] = [], now: Date = Date(),
                            calendar: Calendar = .current) -> WidgetSnapshot {
        let labels = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.label) })
        let urgent = messages
            .filter { !$0.isRead && ($0.importance ?? 0) >= 0.7 }
            .sorted { ($0.importance ?? 0) > ($1.importance ?? 0) }
            .prefix(5)
            .map { EmailItem(id: $0.id, sender: $0.from.display, subject: $0.subject,
                             accountLabel: labels[$0.accountID] ?? "") }
        let today = events
            .filter { $0.status != .dismissed && calendar.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
            .map { EventItem(id: $0.id.uuidString, title: $0.title, start: $0.start) }
        return WidgetSnapshot(urgentEmails: Array(urgent), todaysEvents: today,
                              repliesWaiting: messages.filter(\.awaitingReply).count,
                              generatedAt: now)
    }
}

/// Reads/writes the snapshot in the shared App Group container.
public struct WidgetSnapshotStore: Sendable {
    /// PLACEHOLDER: replace with your App Group id (must match project.yml
    /// entitlements for both the app and the widget target).
    public static let appGroupID = "group.com.example.InboxButler"

    private let fileURL: URL?

    /// Pass `directory` in tests; in the app/widget leave nil to use the App Group.
    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
        self.fileURL = base?.appendingPathComponent("widget-snapshot.json")
    }

    public func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when the App Group is not set up (e.g. in Swift Playgrounds).
    @discardableResult
    public func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
