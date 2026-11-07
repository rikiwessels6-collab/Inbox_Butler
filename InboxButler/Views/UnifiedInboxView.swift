import SwiftUI
import InboxButlerCore

enum InboxFilter: Hashable {
    case all, priority, other, needsReply, newsletters, waiting, drafts, reminders, done
    case account(UUID)
}

/// Three columns on iPad (filters, mail list, message) that collapse to a normal
/// stack on iPhone, where filter chips sit above the list. Search covers every
/// account and works offline.
struct UnifiedInboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: InboxFilter? = .all
    @State private var selectedID: String?
    @State private var search = ""
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @State private var compactColumn: NavigationSplitViewColumn = .content   // iPhone opens on the list
    @State private var reminderTarget: MailMessage?

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar
        } content: {
            list
        } detail: {
            detail
        }
    }

    // MARK: Sidebar (iPad)

    private var sidebar: some View {
        List(selection: $filter) {
            Section {
                row("Inbox", "tray.full", .all, unreadCount(.all))
                row("Important", "star.fill", .priority, unreadCount(.priority))
                row("Other", "tray", .other, unreadCount(.other))
                row("Needs a reply", "arrowshape.turn.up.left", .needsReply, unreadCount(.needsReply))
                row("Drafts ready", "square.and.pencil", .drafts, unreadCount(.drafts))
                row("Waiting on others", "clock", .waiting, model.waitingOnOthers.count)
                row("Newsletters", "newspaper", .newsletters, unreadCount(.newsletters))
            }
            Section {
                row("Reminders", "bell", .reminders, model.snoozedMessages.count)
                row("Done", "checkmark.circle", .done, 0)
            }
            Section {
                ForEach(model.accounts) { account in
                    Label {
                        Text(account.label)
                    } icon: {
                        Image(systemName: account.kind.symbolName).foregroundStyle(account.badgeColor)
                    }
                    .tag(InboxFilter.account(account.id))
                }
            } header: {
                Text("Accounts")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Inbox Butler")
    }

    private func row(_ title: String, _ icon: String, _ value: InboxFilter, _ count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if count > 0 { Text("\(count)").font(.caption).foregroundStyle(Theme.muted) }
        }
        .tag(value)
    }

    // MARK: Mail list

    private var list: some View {
        List(selection: $selectedID) {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .selectionDisabled()

            ForEach(items) { message in
                MessageRow(message: message,
                           account: model.account(for: message.accountID),
                           isPriority: model.isPriority(message),
                           showRecipient: filter == .waiting,
                       reminderBack: model.hasResurfaced(message))
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparatorTint(Theme.hairline)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingActions(for: message) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(for: message) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search all mail")
        .refreshable { await model.refresh() }
        .animation(.snappy, value: filter)
        .overlay(alignment: .bottom) {
            if let toast = model.undoToast {
                UndoToastView(toast: toast) { withAnimation(.snappy) { model.undo(toast) } }
            }
        }
        .animation(.snappy, value: model.undoToast)
        .sensoryFeedback(.success, trigger: model.undoToast?.id)
        .sheet(item: $reminderTarget) { target in
            ReminderSheet(message: target) { date in model.remind(target, at: date) }
        }
        .toolbar {
            if sizeClass == .compact && model.accounts.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(model.accounts) { account in
                            Button(account.label) { filter = .account(account.id) }
                        }
                        Button("All accounts") { filter = .all }
                    } label: {
                        Image(systemName: "person.2")
                    }
                }
            }
        }
        .overlay {
            if model.isRefreshing && model.messages.isEmpty {
                ProgressView()
            } else if items.isEmpty && !model.isRefreshing {
                ContentUnavailableView(search.isEmpty ? "All clear" : "No results",
                                       systemImage: search.isEmpty ? "tray" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "Nothing here right now." : "Try a different search."))
            }
        }
    }

    /// Date, greeting, a one-line summary, the demo banner and (iPhone) filter chips.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                Text(greeting).font(.serif(.largeTitle)).foregroundStyle(Theme.ink)
                Text(summary).font(.subheadline).foregroundStyle(Theme.muted)
            }

            if model.usingDemoData { demoBanner }
            if sizeClass == .compact { chips }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're viewing demo mail").font(.subheadline.weight(.semibold))
                Text("Connect an account to see your own.").font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Connect") { router.tab = .accounts }
                .buttonStyle(PrimaryButtonStyle())
        }
        .card(padding: 14)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Inbox", .all)
                chip("Important", .priority)
                chip("Other", .other)
                chip("Needs reply", .needsReply)
                chip("Drafts", .drafts)
                chip("Waiting", .waiting)
                chip("Newsletters", .newsletters)
                chip("Reminders", .reminders)
                chip("Done", .done)
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String, _ value: InboxFilter) -> some View {
        FilterChip(title: title, count: unreadCount(value),
                   selected: (filter ?? .all) == value) { filter = value }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let message = (model.messages + model.waitingOnOthers).first(where: { $0.id == id }) {
            MessageDetailView(message: message, onTriage: { selectedID = nil }).id(message.id)   // fresh state per message
        } else {
            ZStack {
                Theme.background.ignoresSafeArea()
                ContentUnavailableView("Select a message", systemImage: "envelope.open")
            }
        }
    }

    // MARK: Data

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var summary: String {
        let priority = unreadCount(.priority)
        let reply = unreadCount(.needsReply)
        var parts: [String] = []
        if priority > 0 { parts.append("\(priority) important") }
        if reply > 0 { parts.append("\(reply) need\(reply == 1 ? "s" : "") a reply") }
        return parts.isEmpty ? "You're all caught up." : parts.joined(separator: " · ")
    }

    private func isImportant(_ m: MailMessage) -> Bool {
        !m.isBulk && (model.isPriority(m) || (m.importance ?? 0) >= 0.7)
    }

    private func unreadCount(_ value: InboxFilter) -> Int {
        let inbox = model.inboxMessages
        switch value {
        case .all: return inbox.filter { !$0.isRead }.count
        case .priority: return inbox.filter { !$0.isRead && isImportant($0) }.count
        case .other: return inbox.filter { !$0.isRead && !isImportant($0) && !$0.isBulk }.count
        case .newsletters: return inbox.filter { !$0.isRead && $0.isBulk }.count
        case .needsReply: return inbox.filter(\.awaitingReply).count
        case .waiting: return model.waitingOnOthers.count
        case .drafts: return inbox.filter { model.drafts[$0.id] != nil }.count
        case .reminders: return model.snoozedMessages.count
        case .done: return 0
        case .account(let id): return inbox.filter { !$0.isRead && $0.accountID == id }.count
        }
    }

    private var title: String {
        switch filter ?? .all {
        case .all: return "Inbox"
        case .priority: return "Important"
        case .other: return "Other"
        case .needsReply: return "Needs a reply"
        case .newsletters: return "Newsletters"
        case .waiting: return "Waiting on others"
        case .drafts: return "Drafts ready"
        case .reminders: return "Reminders"
        case .done: return "Done"
        case .account(let id): return model.account(for: id)?.label ?? "Account"
        }
    }

    private var items: [MailMessage] {
        let inbox = model.inboxMessages
        let base: [MailMessage]
        switch filter ?? .all {
        case .all: base = inbox
        case .priority: base = inbox.filter(isImportant)
        case .other: base = inbox.filter { !isImportant($0) && !$0.isBulk }
        case .needsReply: base = inbox.filter(\.awaitingReply)
        case .newsletters: base = inbox.filter(\.isBulk)
        case .waiting: base = model.waitingOnOthers
        case .drafts: base = inbox.filter { model.drafts[$0.id] != nil }
        case .reminders: base = model.snoozedMessages
        case .done: base = model.doneMessages
        case .account(let id): base = inbox.filter { $0.accountID == id }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { m in
            [m.subject, m.snippet, m.from.display, m.from.address].contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: Swipe actions (app-only: the mailbox itself is never changed)

    /// Swipe left: mark done (or, in Done / Reminders, put it back in the inbox).
    @ViewBuilder
    private func trailingActions(for message: MailMessage) -> some View {
        switch filter ?? .all {
        case .waiting:
            EmptyView()
        case .done, .reminders:
            Button { model.restoreToInbox(message) } label: { Label("Back to inbox", systemImage: "tray.and.arrow.down") }
                .tint(Theme.accent)
        default:
            Button { model.markDone(message) } label: { Label("Done", systemImage: "checkmark") }
                .tint(Theme.good)
        }
    }

    /// Swipe right: remind me later.
    @ViewBuilder
    private func leadingActions(for message: MailMessage) -> some View {
        switch filter ?? .all {
        case .waiting, .done:
            EmptyView()
        default:
            Button { reminderTarget = message } label: { Label("Remind", systemImage: "clock") }
                .tint(Color(hex: 0x8A63D2))
        }
    }
}

// MARK: - Row

private struct MessageRow: View {
    let message: MailMessage
    let account: MailAccount?
    let isPriority: Bool
    let showRecipient: Bool
    var reminderBack: Bool = false

    private var unread: Bool { !message.isRead && !showRecipient }
    private var name: String { showRecipient ? "To \(message.to.first?.display ?? "")" : message.from.display }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Avatar(name: showRecipient ? (message.to.first?.display ?? "?") : message.from.display, size: 44)
                if unread {
                    Circle().fill(Theme.accent).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("Unread")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(unread ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if isPriority {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold)
                            .accessibilityLabel("Priority sender")
                    }
                    Spacer(minLength: 8)
                    Text(ShortDate.string(message.receivedAt))
                        .font(.caption)
                        .foregroundStyle(unread ? Theme.accent : Theme.muted)
                }
                Text(message.subject)
                    .font(.subheadline.weight(unread ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(message.snippet)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                tags
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var tags: some View {
        let hasTags = account != nil || !message.attachments.isEmpty || message.awaitingReply || message.isBulk || reminderBack
        if hasTags {
            HStack(spacing: 8) {
                if let account {
                    HStack(spacing: 4) {
                        Circle().fill(account.badgeColor).frame(width: 6, height: 6)
                        Text(account.label).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                if !message.attachments.isEmpty {
                    Image(systemName: "paperclip").font(.caption2).foregroundStyle(Theme.muted)
                        .accessibilityLabel("Has attachments")
                }
                if reminderBack { PillLabel(text: "Reminder", systemImage: "bell.fill", tint: Theme.accent) }
                if message.awaitingReply { PillLabel(text: "Reply", systemImage: "arrowshape.turn.up.left", tint: Theme.warn) }
                if message.isBulk { PillLabel(text: "Newsletter", systemImage: "newspaper") }
            }
            .padding(.top, 2)
        }
    }
}
