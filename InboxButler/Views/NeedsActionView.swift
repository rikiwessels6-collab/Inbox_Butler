import SwiftUI
import InboxButlerCore

struct NeedsActionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    var limit: Int? = nil
    @State private var selectedMessage: MailMessage?
    @State private var reminder: Action?
    @State private var selectedInvite: Action?
    @State private var showNotificationPermission = false

    private struct Action: Identifiable {
        var id: UUID { proposal.id }
        let proposal: EventProposal
        let message: MailMessage
    }

    private var actions: [Action] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.clock)
        guard let end = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        let messages = Dictionary(uniqueKeysWithValues: model.inboxMessages.map { ($0.id, $0) })
        return model.briefingSuggestions(from: today, to: end)
            .filter { $0.isDeadline == true || $0.source == .calendarFile }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
            .compactMap { proposal in
                messages[proposal.sourceMessageID].map { Action(proposal: proposal, message: $0) }
            }
    }

    private var gmailNeedsAttention: Bool {
        model.accounts.contains { $0.kind == .gmail && model.errors[$0.id] != nil }
    }

    var body: some View {
        let all = actions
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if limit != nil {
                    HStack {
                        Text("Needs action").font(.headline)
                        Spacer()
                        Button("Open list") { router.showsActions = true }.font(.subheadline)
                    }
                }
                mailStatus
                if all.isEmpty {
                    Text(gmailNeedsAttention ? "Reconnect to check for deadlines and invites."
                         : model.isRefreshing ? "Checking for deadlines and invites…"
                         : "No deadlines or invites to review.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(all.prefix(limit ?? all.count)) { action in
                    row(action)
                }
                if limit == nil {
                    let drafts = model.inboxMessages.filter { model.draft(for: $0) != nil }
                    if !drafts.isEmpty {
                        SectionLabel(text: "Replies to review")
                        ForEach(drafts.prefix(3)) { message in
                            Button { selectedMessage = message } label: {
                                Label(message.subject, systemImage: "square.and.pencil")
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh() }
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
        .sheet(item: $selectedInvite) { action in
            NavigationStack {
                ScrollView {
                    EventProposalRow(original: action.proposal)
                        .padding(20)
                }
                .background(Theme.background)
                .navigationTitle("Review invite")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { selectedInvite = nil }
                    }
                }
            }
        }
        .sheet(item: $reminder) { action in
            ReminderSheet(message: action.message, suggestedDate: reminderDate(for: action.proposal)) { date in
                model.remind(action.message, at: date)
            }
        }
        .alert("Allow reminder notifications", isPresented: $showNotificationPermission) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on notifications for Inbox Butler in Settings to receive your reminders.")
        }
        .overlay(alignment: .bottom) {
            if let toast = model.undoToast {
                UndoToastView(toast: toast) { model.undo(toast) }
            }
        }
    }

    private func row(_ action: Action) -> some View {
        let deadline = action.proposal.isDeadline == true
        return VStack(alignment: .leading, spacing: 8) {
            Label(when(action.proposal), systemImage: deadline ? "clock" : "calendar.badge.plus")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(deadline ? action.message.subject : action.proposal.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            if deadline, let evidence = action.proposal.evidence {
                Text(evidence).font(.footnote).foregroundStyle(Theme.muted).lineLimit(4)
            }
            ViewThatFits {
                HStack { rowButtons(action, deadline: deadline) }
                VStack(alignment: .leading) { rowButtons(action, deadline: deadline) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }

    @ViewBuilder private func rowButtons(_ action: Action, deadline: Bool) -> some View {
        if deadline {
            Button("Remind me") {
                Task {
                    if await model.notificationStatus() != .authorized {
                        await model.requestNotificationPermission()
                    }
                    if await model.notificationStatus() == .authorized { reminder = action }
                    else { showNotificationPermission = true }
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Source") { selectedMessage = action.message }.buttonStyle(.bordered)
        } else {
            Button("Review invite") { selectedInvite = action }.buttonStyle(.borderedProminent)
            Button("Source") { selectedMessage = action.message }.buttonStyle(.bordered)
        }
        Menu {
            Button(deadline ? "Mark handled" : "Dismiss invite") { model.dismiss(action.proposal) }
        } label: {
            Image(systemName: "ellipsis.circle").imageScale(.large)
        }
        .accessibilityLabel("More actions")
    }

    private func when(_ proposal: EventProposal) -> String {
        let date = proposal.start.formatted(date: .abbreviated, time: proposal.isAllDay ? .omitted : .shortened)
        if proposal.isDeadline != true { return date }
        let overdue = (proposal.isAllDay ? Calendar.current.startOfDay(for: model.clock) : model.clock) > proposal.start
        return overdue ? "Overdue · \(date)" : "Due \(date)"
    }

    private func reminderDate(for proposal: EventProposal) -> Date? {
        let calendar = Calendar.current
        let suggested = proposal.isAllDay
            ? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: proposal.start)
            : calendar.date(byAdding: .hour, value: -1, to: proposal.start)
        return suggested.flatMap { $0 > Date() ? $0 : nil }
    }

    @ViewBuilder private var mailStatus: some View {
        if gmailNeedsAttention {
            VStack(alignment: .leading, spacing: 4) {
                Button("Reconnect Gmail") { selectedMessage = nil; router.openAccounts() }
                if let date = model.lastGmailCheck {
                    Text("Last checked \(date.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.footnote).foregroundStyle(Theme.muted)
        } else if model.usingDemoData || !model.accounts.contains(where: { $0.kind == .gmail }) {
            Button("Connect Gmail") { router.openAccounts() }.font(.subheadline)
        } else if let date = model.lastGmailCheck {
            Text("Gmail checked \(date.formatted(.relative(presentation: .named)))")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}
