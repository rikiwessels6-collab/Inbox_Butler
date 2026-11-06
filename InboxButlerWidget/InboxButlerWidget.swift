import WidgetKit
import SwiftUI
import InboxButlerCore

// Widget extension target (see project.yml). Needs the App Group set up: see README.md.
// This target links InboxButlerCore and reads the snapshot the app writes into
// the shared App Group. It never touches mail, tokens or the database.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore().load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshotStore().load() ?? WidgetSnapshot())
        // The app also calls WidgetCenter.reloadAllTimelines() after each sync;
        // this is the fallback refresh.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

/// Priority senders and urgent mail come first, then today's events, then replies waiting.
struct InboxButlerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemMedium: medium
        default: small
        }
    }

    /// One mail line: star for priority senders, sender in bold, then subject.
    private func row(_ item: WidgetSnapshot.EmailItem, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if item.isPriority { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption2) }
                Text(item.sender).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Text(item.subject).font(.caption).lineLimit(lines).foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(snap.priorityUnreadCount) priority", systemImage: "star.fill")
                .font(.headline)
            if let first = snap.urgentEmails.first {
                row(first, lines: 2)
            } else {
                Text("Nothing urgent").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(footer).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Important").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(snap.urgentEmails.prefix(3)) { row($0) }
                if snap.urgentEmails.isEmpty { Text("Nothing urgent").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(snap.todaysEvents.prefix(3)) { event in
                    Text("\(event.start, style: .time) \(event.title)").font(.caption).lineLimit(1)
                }
                if snap.todaysEvents.isEmpty { Text("No events").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Label("\(snap.repliesWaiting) replies waiting", systemImage: "arrowshape.turn.up.left")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading) {
            Text("\(snap.priorityUnreadCount) priority · \(snap.repliesWaiting) waiting").font(.headline)
            if let first = snap.urgentEmails.first {
                Text("\(first.sender): \(first.subject)").font(.caption).lineLimit(1)
            } else if let event = snap.todaysEvents.first {
                Text("\(event.start, style: .time) \(event.title)").font(.caption)
            }
        }
    }

    private var footer: String {
        if let event = snap.todaysEvents.first { return "\(event.title)" }
        return "\(snap.repliesWaiting) replies waiting"
    }
}

@main
struct InboxButlerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InboxButlerWidget", provider: SnapshotProvider()) { entry in
            InboxButlerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Inbox Butler")
        .description("Urgent emails, today's events and replies waiting.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
