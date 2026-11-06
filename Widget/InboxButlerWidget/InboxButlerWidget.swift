import WidgetKit
import SwiftUI
import InboxButlerCore

// XCODE ONLY. Swift Playgrounds cannot build widget extensions.
// Setup steps: see "Enabling the widget" in the repo README.md.
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

struct InboxButlerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(entry.snapshot.urgentEmails.count) urgent", systemImage: "exclamationmark.envelope")
                .font(.headline)
            if let first = entry.snapshot.urgentEmails.first {
                Text(first.subject).font(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
            Label("\(entry.snapshot.repliesWaiting) replies waiting", systemImage: "arrowshape.turn.up.left")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Urgent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entry.snapshot.urgentEmails.prefix(3)) { item in
                    Text("\(item.sender): \(item.subject)").font(.caption).lineLimit(1)
                }
                Spacer(minLength: 0)
                Label("\(entry.snapshot.repliesWaiting) waiting", systemImage: "arrowshape.turn.up.left")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entry.snapshot.todaysEvents.prefix(3)) { event in
                    Text("\(event.start, style: .time) \(event.title)").font(.caption).lineLimit(1)
                }
                if entry.snapshot.todaysEvents.isEmpty {
                    Text("No events").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading) {
            Text("\(entry.snapshot.urgentEmails.count) urgent · \(entry.snapshot.repliesWaiting) waiting")
                .font(.headline)
            if let event = entry.snapshot.todaysEvents.first {
                Text("\(event.start, style: .time) \(event.title)").font(.caption)
            }
        }
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
