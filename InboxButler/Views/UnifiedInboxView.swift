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
    @State private var todayEvents: [ExistingEvent] = []
    @State private var showMenu = false
    @State private var showBrief = false
    @State private var confirmDoneAll = false
    @State private var composeNew = false
    @State private var noMailAlert = false
    @State private var rsvp: RSVPReply?

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
            if sizeClass != .compact || model.usingDemoData {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }

            if showCaughtUp {
                CaughtUpCard()
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }

            if showBundle {
                bundleRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .selectionDisabled()
            }

            ForEach(items) { message in
                MessageRow(message: message,
                           account: model.accounts.count > 1 ? model.account(for: message.accountID) : nil,
                           isPriority: model.isPriority(message),
                           showRecipient: filter == .waiting,
                       reminderBack: model.hasResurfaced(message),
                       onRSVP: { answer in rsvp = RSVPReply(message: message, answer: answer) })
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
        .navigationTitle(sizeClass == .compact ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sizeClass == .compact)
        .safeAreaInset(edge: .bottom, spacing: 0) { if sizeClass == .compact { splitBar } }
        .searchable(text: $search, prompt: "Search all mail")
        .refreshable { await model.refresh(); await loadToday() }
        .task(id: model.calendarAccess) { await loadToday() }
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
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMenu = true } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Menu")
                        .accessibilityIdentifier("inbox-menu")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { confirmDoneAll = true } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Mark everything here as done")
                    .disabled(items.isEmpty || [.done, .reminders, .waiting].contains(filter ?? .all))
                Button { showBrief = true } label: { Image(systemName: todayBrief.isEmpty ? "sparkle" : "sparkles") }
                    .accessibilityLabel("Today")
                    .accessibilityIdentifier("inbox-today")
                Button { if MailComposer.canSend { composeNew = true } else { noMailAlert = true } } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .sheet(isPresented: $showMenu) { menuSheet }
        .sheet(isPresented: $showBrief) { briefSheet }
        .sheet(isPresented: $composeNew) {
            MailComposer(to: [], subject: "", body: "", preferredFrom: nil) { _ in composeNew = false }.ignoresSafeArea()
        }
        .sheet(item: $rsvp) { reply in
            MailComposer(to: [reply.message.from.address], subject: ReplyFormatter.subject(reply.message.subject),
                         body: reply.text, preferredFrom: model.account(for: reply.message.accountID)?.emailAddress) { _ in rsvp = nil }
                .ignoresSafeArea()
        }
        .alert("Mail isn't set up on this device", isPresented: $noMailAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("Add an account in the iOS Mail app to send from Inbox Butler. Nothing is ever sent without you tapping Send.") }
        .confirmationDialog("Mark \(items.count) as done?", isPresented: $confirmDoneAll, titleVisibility: .visible) {
            Button("Mark all done") { for m in items { model.markDone(m) } }
        } message: {
            Text("They leave this inbox only. Your real mailbox isn't touched, and you can find them under Done.")
        }
        .overlay {
            if model.isRefreshing && model.messages.isEmpty {
                ProgressView()
            } else if items.isEmpty && !model.isRefreshing && !showCaughtUp {
                ContentUnavailableView(search.isEmpty ? "All clear" : "No results",
                                       systemImage: search.isEmpty ? "tray" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "Nothing here right now." : "Try a different search."))
            }
        }
    }

    private var todayBrief: TodayBrief {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(172_800)
        return TodayBrief.make(messages: model.inboxMessages, events: todayEvents,
                               suggestions: model.suggestedEvents(from: start, to: end))
    }

    private func loadToday() async {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        todayEvents = await model.calendarEvents(from: start, to: end)
    }

    // MARK: Menu, Today sheet and the split bar

    private var menuSheet: some View {
        NavigationStack {
            sidebar
                .navigationTitle("Inbox Butler")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showMenu = false } } }
                .onChange(of: filter) { _, _ in showMenu = false }
        }
        .presentationDetents([.medium, .large])
    }

    private var briefSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if todayBrief.isEmpty {
                        Text("Nothing needs you today. Enjoy the quiet.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    } else {
                        TodayCard(brief: todayBrief) { id in
                            selectedID = id
                            compactColumn = .detail
                            showBrief = false
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showBrief = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Splits live in a floating bar at the bottom, within thumb reach.
    private var splitBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                splitItem("Inbox", .all)
                splitItem("Important", .priority)
                splitItem("Other", .other)
                splitItem("Needs reply", .needsReply)
                splitItem("Drafts", .drafts)
                splitItem("Waiting", .waiting)
                splitItem("Newsletters", .newsletters)
                splitItem("Reminders", .reminders)
                splitItem("Done", .done)
            }
            .padding(.horizontal, 24)
            .frame(height: 54)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func splitItem(_ title: String, _ value: InboxFilter) -> some View {
        let selected = (filter ?? .all) == value
        let count = unreadCount(value)
        return Button { withAnimation(.snappy) { filter = value } } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 17, weight: selected ? .semibold : .regular))
                if count > 0 { Text("\(count)").font(.system(size: 15)).foregroundStyle(Theme.muted) }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var quietCount: Int { model.inboxMessages.filter(isQuiet).count }
    private var showBundle: Bool { (filter ?? .all) == .all && search.isEmpty && quietCount > 0 }

    /// One tidy row for all the newsletters and promotions, instead of dozens of rows of noise.
    private var bundleRow: some View {
        Button { withAnimation(.snappy) { filter = .newsletters } } label: {
            HStack(spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.title3).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(quietCount) newsletters and promotions").font(.subheadline.weight(.semibold))
                    Text("Set aside so your inbox shows what matters").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newsletter-bundle")
    }

    /// Date, greeting, a one-line summary, the demo banner and (iPhone) filter chips.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sizeClass != .compact {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                    Text(greeting).font(.serif(.largeTitle)).foregroundStyle(Theme.ink)
                    Text(summary).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }

            if model.usingDemoData { demoBanner }
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

    /// The landscape reward for an empty main inbox (not for searches or special lists).
    private var showCaughtUp: Bool {
        guard items.isEmpty, search.isEmpty, !model.isRefreshing else { return false }
        switch filter ?? .all {
        case .all, .priority, .other: return true
        default: return false
        }
    }

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

    /// Important = a priority sender, something that needs you (security alert, invoice,
    /// appointment, an unanswered reply), or mail the scorer rates highly.
    private func isImportant(_ m: MailMessage) -> Bool {
        model.isPriority(m) || m.awaitingReply || MessageLabeler.isActionable(m)
            || (!m.isBulk && (m.importance ?? 0) >= 0.7)
    }

    /// Marketing and mailing lists that need nothing from you. Set aside in one row.
    private func isQuiet(_ m: MailMessage) -> Bool {
        m.isBulk && !isImportant(m)
    }

    private func unreadCount(_ value: InboxFilter) -> Int {
        let inbox = model.inboxMessages
        switch value {
        case .all: return inbox.filter { !$0.isRead }.count
        case .priority: return inbox.filter { !$0.isRead && isImportant($0) }.count
        case .other: return inbox.filter { !$0.isRead && !isImportant($0) && !$0.isBulk }.count
        case .newsletters: return inbox.filter { !$0.isRead && isQuiet($0) }.count
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
        case .all: base = inbox.filter { !isQuiet($0) }
        case .priority: base = inbox.filter(isImportant)
        case .other: base = inbox.filter { !isImportant($0) && !$0.isBulk }
        case .needsReply: base = inbox.filter(\.awaitingReply)
        case .newsletters: base = inbox.filter(isQuiet)
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

/// A tap on YES / MAYBE / NO in an invite row. Opens the system mail sheet with the answer filled
/// in; nothing is sent until the person taps Send there.
struct RSVPReply: Identifiable {
    enum Answer: String { case yes = "YES", maybe = "MAYBE", no = "NO" }
    let id = UUID()
    let message: MailMessage
    let answer: Answer

    var text: String {
        let first = ReplyFormatter.firstName(message.from.display)
        let line: String
        switch answer {
        case .yes: line = "Yes, I'll be there."
        case .maybe: line = "I might be able to make it. I'll confirm as soon as I know."
        case .no: line = "Sorry, I can't make it."
        }
        return "Hi \(first),\n\n\(line)\n\nThanks,\n\n" + ReplyFormatter.quoted(original: message.snippet, sender: message.from.display, date: message.receivedAt)
    }
}

/// One dense row: sender, date, subject, preview and your own labels. No avatars, so more mail
/// fits on screen. Invites get a calendar mark and one-tap YES / MAYBE / NO.
struct MessageRow: View {
    let message: MailMessage
    let account: MailAccount?
    let isPriority: Bool
    let showRecipient: Bool
    var reminderBack: Bool = false
    var onRSVP: ((RSVPReply.Answer) -> Void)? = nil

    private var unread: Bool { !message.isRead && !showRecipient }
    private var name: String { showRecipient ? "To \(message.to.first?.display ?? "")" : message.from.display }
    private var smartLabels: [MessageLabel] { MessageLabeler.labels(for: message, max: 2) }
    private var isInvite: Bool {
        message.attachments.contains { $0.kind == .calendar }
            || smartLabels.contains { $0.kind == .meeting || $0.kind == .appointment }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.system(size: 19, weight: unread ? .semibold : .regular))
                    .foregroundStyle(unread ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                if isPriority {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold)
                        .accessibilityLabel("Priority sender")
                }
                Spacer(minLength: 8)
                Text(ShortDate.string(message.receivedAt))
                    .font(.subheadline)
                    .foregroundStyle(unread ? Theme.accent : Theme.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(message.subject)
                    .font(.system(size: 18, weight: unread ? .medium : .regular))
                    .foregroundStyle(unread ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isInvite {
                    Image(systemName: "calendar").font(.body).foregroundStyle(Theme.muted)
                        .accessibilityLabel("Calendar invite")
                }
            }
            Text(message.isBulk ? PreviewText.clean(message.snippet) : PreviewText.gist(message.snippet))
                .font(.system(size: 17))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
            chips
            if isInvite, let onRSVP, !showRecipient { rsvpButtons(onRSVP) }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var chips: some View {
        let own = Array(message.labels.prefix(3))
        let smart: [MessageLabel] = own.count >= 2 ? [] : Array(smartLabels.prefix(2 - own.count))
        let showAccount = account != nil
        if !own.isEmpty || !smart.isEmpty || message.awaitingReply || reminderBack || showAccount {
            HStack(spacing: 8) {
                if reminderBack { PillLabel(text: "Reminder", systemImage: "bell.fill", tint: Theme.accent) }
                if message.awaitingReply { PillLabel(text: "Reply", systemImage: "arrowshape.turn.up.left", tint: Theme.warn) }
                ForEach(own, id: \.self) { label in
                    Text(label.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background((label.colorHex.map { Color(hex: $0).opacity(0.38) }) ?? Theme.surface,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                ForEach(smart) { label in
                    PillLabel(text: label.title, systemImage: label.symbolName, tint: label.tint)
                }
                if showAccount, let account {
                    HStack(spacing: 4) {
                        Circle().fill(account.badgeColor).frame(width: 6, height: 6)
                        Text(account.label).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func rsvpButtons(_ onRSVP: @escaping (RSVPReply.Answer) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").foregroundStyle(Theme.accent).frame(width: 36)
            ForEach([RSVPReply.Answer.yes, .maybe, .no], id: \.self) { answer in
                Button { onRSVP(answer) } label: {
                    Text(answer.rawValue)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply \(answer.rawValue.lowercased()) to the invite")
            }
        }
        .padding(.top, 4)
    }
}
