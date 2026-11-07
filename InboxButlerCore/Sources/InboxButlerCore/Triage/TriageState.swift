import Foundation

/// App-only "Done" and "Remind me" state for one message.
///
/// IMPORTANT: this never touches the real mailbox. Marking something Done or setting a
/// reminder only hides it inside Inbox Butler; the email stays exactly where it is on the
/// server.
public struct TriageState: Codable, Equatable, Sendable {
    public var isDone: Bool
    /// The message is hidden until this time, then comes back to the top of the inbox.
    public var remindAt: Date?
    public var updatedAt: Date

    public init(isDone: Bool = false, remindAt: Date? = nil, updatedAt: Date = Date()) {
        self.isDone = isDone
        self.remindAt = remindAt
        self.updatedAt = updatedAt
    }
}

public enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case laterToday, tomorrowMorning, thisWeekend, nextWeek

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .laterToday: return "Later today"
        case .tomorrowMorning: return "Tomorrow morning"
        case .thisWeekend: return "This weekend"
        case .nextWeek: return "Next week"
        }
    }

    public var symbolName: String {
        switch self {
        case .laterToday: return "clock"
        case .tomorrowMorning: return "sunrise"
        case .thisWeekend: return "figure.walk"
        case .nextWeek: return "calendar"
        }
    }
}

/// The rules for what is hidden, what has come back, and when reminders fire.
public enum TriageLogic {
    /// Hidden from the main inbox: marked Done, or a reminder that hasn't arrived yet.
    public static func isHidden(_ state: TriageState?, now: Date = Date()) -> Bool {
        guard let state else { return false }
        if state.isDone { return true }
        if let remindAt = state.remindAt, remindAt > now { return true }
        return false
    }

    public static func isDone(_ state: TriageState?) -> Bool { state?.isDone == true }

    /// Waiting for its reminder time.
    public static func isSnoozed(_ state: TriageState?, now: Date = Date()) -> Bool {
        guard let state, !state.isDone, let remindAt = state.remindAt else { return false }
        return remindAt > now
    }

    /// A reminder that has fired: show it again, at the top, marked as a reminder.
    public static func hasResurfaced(_ state: TriageState?, now: Date = Date()) -> Bool {
        guard let state, !state.isDone, let remindAt = state.remindAt else { return false }
        return remindAt <= now
    }

    /// Presets that still make sense right now (no "Later today" late in the evening, and no
    /// "This weekend" on the weekend itself).
    public static func availablePresets(now: Date = Date(), calendar: Calendar = .current) -> [ReminderPreset] {
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)   // 1 = Sunday ... 7 = Saturday
        return ReminderPreset.allCases.filter { preset in
            switch preset {
            case .laterToday: return hour < 19
            case .thisWeekend: return weekday != 1 && weekday != 7
            default: return true
            }
        }
    }

    public static func date(for preset: ReminderPreset, from now: Date = Date(), calendar: Calendar = .current) -> Date {
        func at(_ day: Date, hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        switch preset {
        case .laterToday:
            // Three hours on, but never later than 9pm and never before the next full hour.
            let candidate = now.addingTimeInterval(3 * 3_600)
            let cap = at(now, hour: 21)
            return min(candidate, cap) > now ? min(candidate, cap) : now.addingTimeInterval(3_600)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return at(tomorrow, hour: 8)
        case .thisWeekend:
            let next = calendar.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? now
            return at(next, hour: 9)
        case .nextWeek:
            let next = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? now
            return at(next, hour: 8)
        }
    }
}

/// Saves triage state as local JSON (never uploaded).
public struct TriageStore: Sendable {
    private let fileURL: URL
    private let limit = 5_000

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("Triage.json")
    }

    public func all() -> [String: TriageState] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: TriageState].self, from: data)) ?? [:]
    }

    /// Sets (or, with nil, clears) a message's state.
    public func set(_ state: TriageState?, for messageID: String) {
        var states = all()
        states[messageID] = state
        write(states)
    }

    public func removeMessages(withPrefix prefix: String) {
        write(all().filter { !$0.key.hasPrefix(prefix) })
    }

    private func write(_ states: [String: TriageState]) {
        var kept = states
        if kept.count > limit {
            let newest = kept.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(limit)
            kept = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(kept).write(to: fileURL, options: .atomic)
    }
}
