import SwiftUI
import InboxButlerCore

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    @State private var events: [ExistingEvent] = []
    @State private var selectedMessage: MailMessage?

    private var day: Date { Calendar.current.startOfDay(for: model.clock) }

    private var agenda: [TodayBrief.Item] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: day) ?? day
        let messages = model.inboxMessages.filter { model.errors[$0.accountID] == nil }
        let availableIDs = Set(messages.map(\.id))
        let suggestions = model.briefingSuggestions(from: day, to: horizon)
            .filter { availableIDs.contains($0.sourceMessageID) }
        return TodayBrief.make(messages: [], events: events, suggestions: suggestions, now: model.clock).items
    }

    private var gmailNeedsAttention: Bool {
        model.accounts.contains { $0.kind == .gmail && model.errors[$0.id] != nil }
    }

    private var drafts: [MailMessage] {
        Array(model.inboxMessages.filter { model.draft(for: $0) != nil }.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let items = agenda
                let layout = sizeClass == .compact
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                VStack(alignment: .leading, spacing: 24) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    layout {
                        VStack(alignment: .leading, spacing: 20) {
                            group("On your calendar", items: items.filter { $0.kind == .allDay || $0.kind == .event },
                                  empty: model.calendarAccess == .granted ? "No more events today." : "Calendar access is off.")
                            if model.calendarAccess == .notDetermined && !model.usingDemoData {
                                Button("Allow calendar access") { Task { await model.requestCalendarAccess() } }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 20) {
                            group("Due this week", items: items.filter { $0.kind == .deadline },
                                  empty: gmailNeedsAttention ? "Check Gmail to update deadlines." : "No deadlines found.")
                            let suggested = items.filter { $0.kind == .suggestion }
                            if !suggested.isEmpty { group("From email", items: suggested) }
                            if !drafts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionLabel(text: "Replies to review")
                                    ForEach(drafts) { message in
                                        Button { selectedMessage = message } label: {
                                            Label(message.subject, systemImage: "square.and.pencil")
                                                .multilineTextAlignment(.leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    mailStatus
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh(); await loadCalendar() }
            .task(id: day) { await model.refreshCalendars(); await loadCalendar() }
            .task(id: model.calendarAccess) { await loadCalendar() }
            .onChange(of: phase) { _, value in
                if value == .active { Task { await model.refreshCalendars(); await loadCalendar() } }
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

    private func group(_ title: String, items: [TodayBrief.Item], empty: String = "") -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: title)
            if items.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(items) { item in
                if item.id != items.first?.id { Divider().overlay(Theme.hairline) }
                if let id = item.messageID, let message = model.messages.first(where: { $0.id == id }) {
                    Button { selectedMessage = message } label: {
                        HStack {
                            itemText(item)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    itemText(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func itemText(_ item: TodayBrief.Item) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(item.detail).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder private var mailStatus: some View {
        if gmailNeedsAttention {
            Button { router.openAccounts() } label: {
                Label("Gmail needs attention", systemImage: "exclamationmark.circle")
            }
        } else if model.isRefreshing {
            ProgressView("Checking Gmail")
        } else if let date = model.lastGmailCheck, model.accounts.contains(where: { $0.kind == .gmail }) {
            Text("Gmail checked \(date.formatted(.relative(presentation: .named)))")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else if model.usingDemoData || !model.accounts.contains(where: { $0.kind == .gmail }) {
            Button("Connect Gmail") { router.openAccounts() }
        }
    }

    private func loadCalendar() async {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        events = await model.calendarEvents(from: day, to: end)
    }
}
