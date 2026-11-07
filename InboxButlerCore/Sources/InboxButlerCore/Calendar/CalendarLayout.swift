import Foundation

public struct PlacedEvent: Identifiable, Sendable {
    public let event: ExistingEvent
    /// Which column the event sits in when others overlap it (0 = leftmost).
    public let lane: Int
    /// How many columns its overlap group needs.
    public let laneCount: Int
    public var id: String { event.id }
}

/// Lays out one day's timed events so overlapping ones sit side by side instead of on top
/// of each other (like a real calendar app).
public enum CalendarLayout {
    public static func place(_ events: [ExistingEvent]) -> [PlacedEvent] {
        let sorted = events.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        var placed: [PlacedEvent] = []
        var cluster: [(ExistingEvent, Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(laneEnds.count, 1)
            placed += cluster.map { PlacedEvent(event: $0.0, lane: $0.1, laneCount: count) }
            cluster = []; laneEnds = []
        }

        for event in sorted {
            if !cluster.isEmpty, event.start >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= event.start }) {
                laneEnds[free] = event.end
                cluster.append((event, free))
            } else {
                laneEnds.append(event.end)
                cluster.append((event, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, event.end)
        }
        flush()
        return placed
    }
}
