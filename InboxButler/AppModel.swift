import SwiftUI
import InboxButlerCore
import WidgetKit
import UserNotifications

enum AddAccountError: LocalizedError {
    case googleNotConfigured
    case duplicate(String)
    var errorDescription: String? {
        switch self {
        case .googleNotConfigured:
            return "Google sign-in isn't set up yet. Add your client ID in AppConfig.swift (see docs/SETUP_GOOGLE.md)."
        case .duplicate(let email):
            return "\(email) is already connected."
        }
    }
}

/// Holds app-wide state for the UI: accounts, the merged inbox, sync errors.
/// With no accounts connected it shows demo data; once you connect one, only
/// your real mail is shown. Real mail is cached locally (SwiftData) so the
/// inbox appears instantly and works offline.
@Observable
@MainActor
final class AppModel {
    /// Single shared instance (also used by the background refresh task).
    static let shared = AppModel()

    private(set) var prioritySenders: [PrioritySender] = []
    /// Recently sent mail (reply tracking, suggestions).
    private(set) var sent: [MailMessage] = []
    /// Mail you sent that nobody has answered yet.
    private(set) var waitingOnOthers: [MailMessage] = []
    /// People you might want as priority senders, based on your own habits.
    private(set) var suggestions: [SenderSuggestion] = []
    /// Calendar access and the calendars events can be added to (iCloud, Google, family...).
    private(set) var calendarAccess: CalendarAccess = .notDetermined
    private(set) var calendars: [CalendarInfo] = []
    /// The calendar new events go to; remembered between messages. nil = device default.
    var targetCalendarID: String? = UserDefaults.standard.string(forKey: "targetCalendarID") {
        didSet { UserDefaults.standard.set(targetCalendarID, forKey: "targetCalendarID") }
    }
    private(set) var accounts: [MailAccount] = []
    private(set) var messages: [MailMessage] = []
    private(set) var errors: [UUID: String] = [:]
    private(set) var isRefreshing = false
    /// True while showing fake demo mail (no real account connected).
    private(set) var usingDemoData = false

    private var engine = SyncEngine(providers: [])

    private let accountStore = AccountStore()
    private let senderStore = PrioritySenderStore()
    private let notifiedStore = NotifiedStore()
    private let notifier = NotificationService()
    private let secrets = KeychainStore()
    private let cache: MessageCache?
    private let proposalStore = EventProposalStore()
    private let calendarWriter = EventKitCalendarWriter()
    private let analyzer = MessageAnalyzer()
    private var providerByAccount: [UUID: any MailProvider] = [:]

    private init() {
        prioritySenders = senderStore.load()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        cache = try? MessageCache()
        accounts = accountStore.load()
        configureProviders()
        // Offline-first: show what we already have before the network answers.
        if !usingDemoData, let cache { messages = cache.load() }
    }

    func account(for id: UUID) -> MailAccount? {
        accounts.first { $0.id == id }
    }

    // MARK: Providers

    private func configureProviders() {
        if accounts.isEmpty {
            let mock = MockData.make()
            usingDemoData = true
            accounts = mock.accounts
            engine = SyncEngine(providers: mock.providers)
            providerByAccount = Dictionary(uniqueKeysWithValues: mock.providers.map { ($0.account.id, $0) })
        } else {
            usingDemoData = false
            let providers = accounts.map(makeProvider)
            engine = SyncEngine(providers: providers)
            providerByAccount = Dictionary(uniqueKeysWithValues: providers.map { ($0.account.id, $0) })
        }
    }

    private func tokenManager(for accountID: UUID) -> GoogleTokenManager {
        GoogleTokenManager(accountID: accountID, auth: GoogleAuth(config: AppConfig.googleOAuth), secrets: secrets)
    }

    private func makeProvider(_ account: MailAccount) -> any MailProvider {
        switch account.kind {
        case .gmail: return GmailProvider(account: account, tokens: tokenManager(for: account.id))
        case .microsoft: return MicrosoftProvider(account: account)
        case .icloud, .imap: return IMAPProvider(account: account)
        }
    }

    // MARK: Adding and removing accounts

    /// Google sign-in (read-only scope), then stores tokens in the Keychain.
    func addGmailAccount() async throws {
        let config = AppConfig.googleOAuth
        guard config.isConfigured else { throw AddAccountError.googleNotConfigured }

        let tokens = try await GoogleSignInFlow().signIn(config: config)
        let id = UUID()
        let manager = tokenManager(for: id)
        try await manager.save(tokens)

        let email: String
        do {
            let probe = MailAccount(id: id, kind: .gmail, emailAddress: "", label: "Gmail", colorIndex: 0)
            email = try await GmailProvider(account: probe, tokens: manager).fetchEmailAddress()
        } catch {
            await manager.signOut()
            throw error
        }

        let existing = usingDemoData ? [] : accounts
        if existing.contains(where: { $0.emailAddress.caseInsensitiveCompare(email) == .orderedSame }) {
            // Same Google grant as the existing account: don't revoke, just drop the duplicate copy.
            await manager.discardLocally()
            throw AddAccountError.duplicate(email)
        }

        if usingDemoData { accounts = []; messages = [] }
        let gmailCount = existing.filter { $0.kind == .gmail }.count
        accounts.append(MailAccount(id: id, kind: .gmail, emailAddress: email,
                                    label: gmailCount == 0 ? "Gmail" : "Gmail \(gmailCount + 1)",
                                    colorIndex: existing.count))
        try? accountStore.save(accounts)
        configureProviders()
        await refresh()
    }

    /// Signs out (revokes Google access), deletes local tokens and cached mail.
    func removeAccount(_ account: MailAccount) async {
        guard !usingDemoData else { return }
        if account.kind == .gmail { await tokenManager(for: account.id).signOut() }
        cache?.remove(accountID: account.id)
        proposalStore.removeMessages(withPrefix: account.id.uuidString + "/")
        accounts.removeAll { $0.id == account.id }
        errors[account.id] = nil
        try? accountStore.save(accounts)
        configureProviders()
        messages = usingDemoData ? [] : (cache?.load() ?? [])
        if usingDemoData { await refresh() }
        publishWidgetSnapshot()
    }

    // MARK: Sync

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let result = await engine.refresh()
        errors = result.errors
        if !result.sent.isEmpty { sent = result.sent }
        if usingDemoData {
            messages = result.messages
        } else if let cache {
            // Only accounts that synced successfully update the cache; accounts
            // that failed (e.g. offline) keep showing their cached mail.
            for account in accounts where result.errors[account.id] == nil {
                cache.sync(accountID: account.id, fetched: result.messages.filter { $0.accountID == account.id })
            }
            cache.prune()
            messages = cache.load()
        } else {
            messages = result.messages
        }
        applyReplyTracking()
        publishWidgetSnapshot()
        await notifyForNewMail()
        await notifyFollowUps()
        await scanPriorityMailForEvents()
        await rescheduleBrief()
    }

    // MARK: Reply tracking and suggestions

    /// Works out (on-device) who is waiting on you and whom you are waiting on.
    /// Skipped when there is no sent mail yet, so an offline start doesn't flag everything.
    private func applyReplyTracking() {
        guard !usingDemoData, !sent.isEmpty else { return }
        let me = Set(accounts.map { $0.emailAddress.lowercased() })
        let status = ReplyTracker.analyze(inbox: messages, sent: sent, myAddresses: me)
        for i in messages.indices { messages[i].awaitingReply = status.awaitingMyReply.contains(messages[i].id) }
        waitingOnOthers = status.awaitingTheirReply
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: AppSettings.dismissedSuggestionsKey) ?? [])
        suggestions = SuggestedSenders.suggest(sent: sent, inbox: messages, existing: prioritySenders, myAddresses: me)
            .filter { !dismissed.contains($0.address) }
    }

    func acceptSuggestion(_ suggestion: SenderSuggestion) {
        addPrioritySender(suggestion.address)
        suggestions.removeAll { $0.address == suggestion.address }
    }

    func dismissSuggestion(_ suggestion: SenderSuggestion) {
        var dismissed = UserDefaults.standard.stringArray(forKey: AppSettings.dismissedSuggestionsKey) ?? []
        dismissed.append(suggestion.address)
        UserDefaults.standard.set(dismissed, forKey: AppSettings.dismissedSuggestionsKey)
        suggestions.removeAll { $0.address == suggestion.address }
    }

    /// Local-only: marks read in the app. Never changes the real mailbox.
    func markReadLocally(_ message: MailMessage) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].isRead = true
        cache?.markReadLocally(message.id)
    }

    /// Writes the small summary the widget reads (App Group file) and asks
    /// WidgetKit to refresh. Contains sender/subject text; see README privacy notes.
    func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot.make(messages: messages, accounts: accounts,
                                           events: usingDemoData ? [] : proposalStore.all(),
                                           priority: prioritySenders,
                                           redact: AppSettings.bool(AppSettings.redactKey, default: false))
        if WidgetSnapshotStore().save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Attachments and calendar events

    /// Reads the full message and its attachments ON THIS DEVICE and proposes events.
    /// Remembers dismissed/added events so they don't come back.
    func analysis(for message: MailMessage) async -> MessageAnalysis? {
        guard let provider = providerByAccount[message.accountID] else { return nil }
        var result = await analyzer.analyze(message, provider: provider)
        if !usingDemoData {
            result.proposals = proposalStore.merge(result.proposals, forMessage: message.id)
            publishWidgetSnapshot()
        }
        return result
    }

    // MARK: Calendar

    func refreshCalendars() async {
        calendarAccess = await calendarWriter.accessState()
        calendars = calendarAccess == .granted ? ((try? await calendarWriter.calendars()) ?? []) : []
        if let id = targetCalendarID, !calendars.contains(where: { $0.id == id }) { targetCalendarID = nil }
    }

    func requestCalendarAccess() async {
        _ = await calendarWriter.requestAccess()
        await refreshCalendars()
    }

    /// Overlaps and "already added?" hints. Informational only: they never block an add.
    func overlap(for proposal: EventProposal) async -> CalendarOverlap {
        guard calendarAccess == .granted else { return .none }
        return CalendarOverlapChecker.classify(proposal, existing: await calendarWriter.nearbyEvents(for: proposal))
    }

    /// Adds the (possibly edited) event to the chosen calendar. Only ever called from the
    /// user tapping "Add" on that event. `original` identifies the stored proposal.
    func addToCalendar(_ edited: EventProposal, original: EventProposal) async throws -> EventProposal {
        try await calendarWriter.add(edited, toCalendar: targetCalendarID)
        await refreshCalendars()   // the first add may have just been granted access
        return markDone(edited, original: original)
    }

    /// Records an event as handled (added, or found to be in the calendar already).
    func markDone(_ edited: EventProposal, original: EventProposal) -> EventProposal {
        var done = edited
        done.status = .confirmed
        if !usingDemoData {
            proposalStore.update(done, replacing: original.fingerprint)
            publishWidgetSnapshot()
        }
        return done
    }

    func dismiss(_ proposal: EventProposal) {
        var dismissed = proposal
        dismissed.status = .dismissed
        if !usingDemoData {
            proposalStore.update(dismissed)
            publishWidgetSnapshot()
        }
    }

    /// Scans new mail from priority senders (max 5 per refresh) so today's events
    /// reach the widget without opening each message. Everything stays on-device.
    private func scanPriorityMailForEvents() async {
        guard !usingDemoData else { return }
        let candidates = messages
            .filter { !$0.isRead && isPriority($0) && !proposalStore.hasScanned($0.id) }
            .prefix(5)
        for message in candidates { _ = await analysis(for: message) }
    }

    // MARK: Priority senders

    func isPriority(_ message: MailMessage) -> Bool {
        prioritySenders.contains(address: message.from.address)
    }

    /// Returns false if `input` isn't a valid address or "@domain", or already exists.
    @discardableResult
    func addPrioritySender(_ input: String) -> Bool {
        guard let sender = PrioritySender(input: input),
              !prioritySenders.contains(where: { $0.pattern == sender.pattern }) else { return false }
        prioritySenders.append(sender)
        persistPriority()
        return true
    }

    func removePrioritySenders(at offsets: IndexSet) {
        prioritySenders.remove(atOffsets: offsets)
        persistPriority()
    }

    private func persistPriority() {
        try? senderStore.save(prioritySenders)
        publishWidgetSnapshot()   // widget ranking depends on the list
    }

    // MARK: Notifications

    /// Notifies only for unread mail from priority senders that we haven't
    /// notified about yet. The very first run just records existing mail so
    /// installing the app doesn't buzz for old messages.
    private func notifyForNewMail() async {
        // Demo mail must never mark "seen" state, or the first real sync would
        // be treated as a later run and notify for the whole inbox.
        guard !usingDemoData else { return }
        guard let notified = notifiedStore.load() else {
            notifiedStore.add(messages.map(\.id))
            return
        }
        let plan = NotificationPlanner.plan(messages: messages, accounts: accounts,
                                            priority: prioritySenders, alreadyNotified: notified)
        // Without permission, just record everything so enabling notifications
        // later doesn't dump a backlog of old mail.
        guard await notifier.status() == .authorized else {
            notifiedStore.add(messages.map(\.id))
            return
        }
        for item in plan { await notifier.post(item) }
        // Record everything except priority mail that was held back by the
        // per-run cap, so it is delivered on the next run.
        let held = Set(NotificationPlanner.plan(messages: messages, accounts: accounts,
                                                priority: prioritySenders,
                                                alreadyNotified: notified.union(plan.map(\.id))).map(\.id))
        notifiedStore.add(messages.map(\.id).filter { !held.contains($0) })
    }

    /// Reminds you about mail you sent to a priority sender that has had no reply.
    private func notifyFollowUps() async {
        guard !usingDemoData, AppSettings.bool(AppSettings.followUpsKey, default: true),
              let notified = notifiedStore.load(), await notifier.status() == .authorized else { return }
        let plan = FollowUpPlanner.plan(awaiting: waitingOnOthers, accounts: accounts,
                                        priority: prioritySenders, alreadyNotified: notified)
        for item in plan { await notifier.post(item, urgent: false) }
        notifiedStore.add(plan.map(\.id))
    }

    /// Schedules (or cancels) the optional 8am summary. Its text is a snapshot from the
    /// last refresh, so it can be slightly stale if the app hasn't updated overnight.
    func rescheduleBrief() async {
        guard AppSettings.bool(AppSettings.briefKey, default: false), await notifier.status() == .authorized else {
            notifier.cancelMorningBrief()
            return
        }
        let calendar = Calendar.current
        guard let next = calendar.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 0),
                                           matchingPolicy: .nextTime) else { return }
        let events = usingDemoData ? [] : proposalStore.all().filter {
            $0.status != .dismissed && calendar.isDate($0.start, inSameDayAs: next)
        }
        let text = MorningBrief.text(priorityUnread: messages.filter { !$0.isRead && isPriority($0) }.count,
                                     needsReply: messages.filter(\.awaitingReply).count,
                                     eventsToday: events.count)
        await notifier.scheduleMorningBrief(at: next, title: text.title, body: text.body)
    }

    func notificationStatus() async -> UNAuthorizationStatus { await notifier.status() }
    func requestNotificationPermission() async { await notifier.requestAuthorization() }

    /// Lets the user see exactly what a priority notification looks like.
    func sendTestNotification() async {
        await notifier.post(PlannedNotification(id: "test-\(UUID().uuidString)", title: "Sam Rivera",
                                                subtitle: "Work", body: "Contract needs signing today"))
    }
}
