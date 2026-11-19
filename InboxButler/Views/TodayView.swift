import SwiftUI
import InboxButlerCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var phase
    @State private var events: [ExistingEvent] = []
    @State private var selectedMessage: MailMessage?

    private var day: Date { Calendar.current.startOfDay(for: model.clock) }

    private var brief: TodayBrief {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: day) ?? day
        return TodayBrief.make(messages: model.inboxMessages, events: events,
                               suggestions: model.briefingSuggestions(from: day, to: horizon),
                               now: model.clock)
    }

    private var gmailStatus: String {
        let accounts = model.accounts.filter { $0.kind == .gmail }
        if model.usingDemoData { return "Sample briefing · Connect Gmail to see your own updates." }
        if accounts.isEmpty { return "Connect Gmail to include important emails and attachments." }
        if accounts.contains(where: { model.errors[$0.id] != nil }) {
            return "Gmail check failed. Pull to retry or check your sign-in in Accounts."
        }
        if let checked = model.lastGmailCheck {
            return "Gmail last checked \(checked.formatted(.relative(presentation: .named)))."
        }
        return "Waiting for your first Gmail check."
    }

    private var warnings: [MailMessage] {
        model.inboxMessages.filter { model.scanWarnings[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.title2.weight(.semibold))
                    Text(gmailStatus).font(.footnote).foregroundStyle(Theme.muted)
                    if model.isRefreshing { ProgressView("Checking mail") }
                    if model.calendarAccess == .notDetermined && !model.usingDemoData {
                        Button("Show today’s calendar") { Task { await model.requestCalendarAccess() } }
                    }
                    if brief.isEmpty {
                        Text("No items in your brief.").foregroundStyle(Theme.muted)
                    } else {
                        TodayCard(brief: brief, onOpen: openMessage)
                    }
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Needs review").font(.headline)
                            ForEach(warnings) { message in
                                Button { selectedMessage = message } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.subject)
                                        ForEach(model.scanWarnings[message.id] ?? [], id: \.self) { note in
                                            Text(note).font(.footnote).foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today")
            .toolbar {
                Button("Inbox", systemImage: "tray") { router.tab = .inbox }
            }
            .refreshable { await model.refresh(); await loadCalendar() }
            .task(id: day) { await loadCalendar() }
            .task(id: model.calendarAccess) { await loadCalendar() }
            .onChange(of: phase) { _, value in
                if value == .active {
                    Task { await loadCalendar(); await model.refresh() }
                }
            }
            .sheet(item: $selectedMessage) { message in
                NavigationStack {
                    MessageDetailView(message: message) { selectedMessage = nil }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { selectedMessage = nil }
                            }
                        }
                }
            }
        }
    }

    private func openMessage(_ id: String) {
        selectedMessage = model.messages.first { $0.id == id }
    }

    private func loadCalendar() async {
        await model.refreshCalendars()
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        events = await model.calendarEvents(from: day, to: end)
    }
}
