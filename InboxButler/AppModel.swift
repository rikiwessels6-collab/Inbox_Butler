import SwiftUI
import InboxButlerCore
import WidgetKit
import UserNotifications

struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let messageID: String
    let previous: TriageState?
}

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
    /// Inbox views the user defined (by their own labels or senders). Stored on this device only.
    private(set) var splits: [InboxSplit] = []
    /// Recently sent mail (reply tracking, suggestions).
    private(set) var sent: [MailMessage] = []
    /// Mail you sent that nobody has answered yet.
    private(set) var waitingOnOthers: [MailMessage] = []
    /// People you might want as priority senders, based on your own habits.
    private(set) var suggestions: [SenderSuggestion] = []
    /// Reply drafts by message id. Written on this device; never sent automatically.
    private(set) var drafts: [String: ReplyDraft] = [:]
    private(set) var isDraftingIDs: Set<String> = []
    /// Why a draft fell back to a simpler one (e.g. the cloud key was rejected), by message id.
    private(set) var draftNotes: [String: String] = [:]
    /// App-only Done / Remind-me state by message id. NEVER changes the real mailbox.
    private(set) var triage: [String: TriageState] = [:]
    /// Updated every 30 seconds so reminders reappear on time.
    private(set) var clock = Date()
    /// "Marked done. Undo" banner.
    var undoToast: UndoToast?
    /// A few lines about the user, used to make drafts more natural.
    private(set) var writerProfile = WriterProfile()
    /// What the app has learned about how you write (on this device).
    private(set) var styleProfile: StyleProfile?
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
    private let splitStore = InboxSplitStore()
    private let notifiedStore = NotifiedStore()
    private let notifier = NotificationService()
    private let secrets = KeychainStore()
    private let cache: MessageCache?
    private let proposalStore = EventProposalStore()
    private let calendarWriter = EventKitCalendarWriter()
    private let analyzer = MessageAnalyzer()
    private let draftStore = DraftStore()
    private let triageStore = TriageStore()
    private let writerStore = WriterProfileStore()
    private let styleStore = StyleProfileStore()
    private var ai: any AIService = DraftAI.make()
    private var providerByAccount: [UUID: any MailProvider] = [:]

    private init() {
        prioritySenders = senderStore.load()
        splits = splitStore.load()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        cache = try? MessageCache()
        accounts = accountStore.load()
        styleProfile = styleStore.load()
        triage = triageStore.all()
        writerProfile = writerStore.load() ?? WriterProfile()
        drafts = Dictionary(draftStore.all().filter { $0.status != .discarded }.map { ($0.inReplyToMessageID, $0) },
                            uniquingKeysWith: { _, new in new })
        configureProviders()
        // Offline-first: show what we already have before the network answers.
        if !usingDemoData, let cache { messages = cache.load() }
        // Let reminders come back on time while the app is open.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                self?.clock = Date()
            }
        }
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
        case .icloud, .imap: return IMAPProvider(account: account, secrets: secrets)
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

    /// Connects an iCloud or other IMAP mailbox. Checks the sign-in works first, then saves the
    /// password in the Keychain. For iCloud, `password` must be an APP-SPECIFIC password.
    func addIMAPAccount(kind: AccountKind, email: String, password: String,
                        host: String = "", port: Int = 993, username: String = "") async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.filter { !$0.isWhitespace }
        let credentials: IMAPCredentials
        if kind == .icloud {
            credentials = .icloud(email: cleanEmail, appPassword: cleanPassword)
        } else {
            let cleanUser = username.trimmingCharacters(in: .whitespaces)
            credentials = IMAPCredentials(host: host.trimmingCharacters(in: .whitespaces), port: port,
                                          username: cleanUser.isEmpty ? cleanEmail : cleanUser, password: cleanPassword)
        }

        let existing = usingDemoData ? [] : accounts
        if existing.contains(where: { $0.emailAddress.caseInsensitiveCompare(cleanEmail) == .orderedSame }) {
            throw AddAccountError.duplicate(cleanEmail)
        }
        try await IMAPProvider.verify(credentials)      // throws a readable error if sign-in fails

        let id = UUID()
        try IMAPProvider.save(credentials, for: id, in: secrets)
        if usingDemoData { accounts = []; messages = [] }
        let sameKind = existing.filter { $0.kind == kind }.count
        let baseLabel = kind == .icloud ? "iCloud" : (credentials.host.split(separator: ".").dropLast().last.map(String.init)?.capitalized ?? "Mail")
        accounts.append(MailAccount(id: id, kind: kind, emailAddress: cleanEmail,
                                    label: sameKind == 0 ? baseLabel : "\(baseLabel) \(sameKind + 1)",
                                    colorIndex: existing.count))
        try? accountStore.save(accounts)
        configureProviders()
        await refresh()
    }

    /// Signs out (revokes Google access), deletes local tokens and cached mail.
    func removeAccount(_ account: MailAccount) async {
        guard !usingDemoData else { return }
        if account.kind == .gmail { await tokenManager(for: account.id).signOut() }
        if account.kind == .icloud || account.kind == .imap { IMAPProvider.removeCredentials(for: account.id, from: secrets) }
        cache?.remove(accountID: account.id)
        proposalStore.removeMessages(withPrefix: account.id.uuidString + "/")
        draftStore.removeMessages(withPrefix: account.id.uuidString + "/")
        triageStore.removeMessages(withPrefix: account.id.uuidString + "/")
        triage = triage.filter { !$0.key.hasPrefix(account.id.uuidString + "/") }
        drafts = drafts.filter { !$0.key.hasPrefix(account.id.uuidString + "/") }
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
        // Drafting and style learning can be slow: run them after the refresh finishes.
        Task { await learnStyleIfNeeded(); await prepareDrafts() }
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
        // Opening a reminder that has come back counts as dealing with it.
        if TriageLogic.hasResurfaced(triage[message.id], now: clock) {
            setTriage(nil, for: message.id)
            notifier.cancelReminder(id: message.id)
        }
    }

    func saveWriterProfile(_ profile: WriterProfile) {
        writerProfile = profile
        writerStore.save(profile)
    }

    // MARK: Triage: Done and Remind me (app-only)

    func isHidden(_ message: MailMessage) -> Bool { TriageLogic.isHidden(triage[message.id], now: clock) }
    func isDone(_ message: MailMessage) -> Bool { TriageLogic.isDone(triage[message.id]) }
    func hasResurfaced(_ message: MailMessage) -> Bool { TriageLogic.hasResurfaced(triage[message.id], now: clock) }

    /// What the inbox shows: everything except Done and not-yet-due reminders. Reminders that
    /// have come back sit at the top.
    var inboxMessages: [MailMessage] {
        messages.filter { !isHidden($0) }.sorted { a, b in
            let (ra, rb) = (hasResurfaced(a), hasResurfaced(b))
            if ra != rb { return ra }
            return a.receivedAt > b.receivedAt
        }
    }

    var snoozedMessages: [MailMessage] {
        messages.filter { TriageLogic.isSnoozed(triage[$0.id], now: clock) }
            .sorted { (triage[$0.id]?.remindAt ?? .distantFuture) < (triage[$1.id]?.remindAt ?? .distantFuture) }
    }

    var doneMessages: [MailMessage] {
        messages.filter { isDone($0) }.sorted { (triage[$0.id]?.updatedAt ?? .distantPast) > (triage[$1.id]?.updatedAt ?? .distantPast) }
    }

    func markDone(_ message: MailMessage) {
        apply(TriageState(isDone: true), to: message, toast: "Marked done")
    }

    func remind(_ message: MailMessage, at date: Date) {
        let when = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        apply(TriageState(remindAt: date), to: message, toast: "Reminder set for \(when)")
    }

    func restoreToInbox(_ message: MailMessage) {
        apply(nil, to: message, toast: "Back in your inbox")
    }

    func undo(_ toast: UndoToast) {
        setTriage(toast.previous, for: toast.messageID)
        notifier.cancelReminder(id: toast.messageID)
        if let previous = toast.previous, let at = previous.remindAt, !previous.isDone, at > Date(),
           let message = messages.first(where: { $0.id == toast.messageID }) {
            Task { await scheduleReminderNotification(for: message, at: at) }
        }
        undoToast = nil
        publishWidgetSnapshot()
    }

    private func apply(_ new: TriageState?, to message: MailMessage, toast text: String) {
        let previous = triage[message.id]
        setTriage(new, for: message.id)
        if let new, !new.isDone, let at = new.remindAt {
            Task { await scheduleReminderNotification(for: message, at: at) }
        } else {
            notifier.cancelReminder(id: message.id)
        }
        let toast = UndoToast(text: text, messageID: message.id, previous: previous)
        undoToast = toast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self?.undoToast?.id == toast.id { self?.undoToast = nil }
        }
        publishWidgetSnapshot()
    }

    private func setTriage(_ state: TriageState?, for id: String) {
        triage[id] = state
        if !usingDemoData { triageStore.set(state, for: id) }
    }

    private func scheduleReminderNotification(for message: MailMessage, at date: Date) async {
        await notifier.scheduleReminder(id: message.id, title: "Back in your inbox",
                                        subtitle: message.from.display, body: message.subject, at: date)
    }

    /// Writes the small summary the widget reads (App Group file) and asks
    /// WidgetKit to refresh. Contains sender/subject text; see README privacy notes.
    func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot.make(messages: inboxMessages, accounts: accounts,
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

    /// Events for the Calendar tab (display only; nothing is stored).
    func calendarEvents(from start: Date, to end: Date) async -> [ExistingEvent] {
        guard calendarAccess == .granted else { return [] }
        return await calendarWriter.events(from: start, to: end)
    }

    /// Events found in email that you haven't added or dismissed yet.
    func suggestedEvents(from start: Date, to end: Date) -> [EventProposal] {
        guard !usingDemoData else { return [] }
        return proposalStore.all().filter { $0.status == .proposed && $0.start >= start && $0.start < end }
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

    /// Downloads an attachment from the user's mail server (for preview).
    func attachmentData(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        guard let provider = providerByAccount[message.accountID] else { throw MailProviderError.notAuthorized }
        return try await provider.fetchAttachment(attachment, in: message)
    }

    /// Prepares an answer to a calendar invite: the person to reply to, the reply text and, when the
    /// invite has a calendar file, a matching calendar reply so the organiser's calendar updates too.
    /// Nothing is sent: the person still reviews it and taps Send in the system mail sheet.
    func prepareRSVP(_ message: MailMessage, _ answer: RSVPReply.Answer) async -> RSVPReply {
        let myAddress = account(for: message.accountID)?.emailAddress ?? ""
        var to = message.from.address
        var ics: Data?
        if let invite = message.attachments.first(where: { $0.kind == .calendar }),
           let data = try? await attachmentData(invite, in: message),
           let reply = ICSReplyBuilder.make(from: String(decoding: data, as: UTF8.self), answer: answer.rsvp,
                                            attendee: myAddress, attendeeName: nil) {
            ics = Data(reply.ics.utf8)
            if let organizer = reply.organizer, organizer.contains("@") { to = organizer }
        }
        return RSVPReply(message: message, answer: answer, to: to, ics: ics)
    }

    /// The message's original HTML (nil if it has none), for the formatted view.
    func htmlBody(for message: MailMessage) async throws -> String? {
        guard let provider = providerByAccount[message.accountID] else { return nil }
        return try await provider.fetchHTMLBody(for: message)
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

    // MARK: Reply drafts

    func isFromMe(_ message: MailMessage) -> Bool {
        accounts.contains { $0.emailAddress.caseInsensitiveCompare(message.from.address) == .orderedSame }
    }

    func draft(for message: MailMessage) -> ReplyDraft? { drafts[message.id] }

    var draftedMessageIDs: Set<String> { Set(drafts.keys) }

    var aiStatusText: String { DraftAI.statusText }

    /// Writes a draft reply on this device. If the AI model fails, falls back to a simple template.
    @discardableResult
    func generateDraft(for message: MailMessage, body: String? = nil) async -> ReplyDraft? {
        guard !isDraftingIDs.contains(message.id) else { return drafts[message.id] }
        isDraftingIDs.insert(message.id)
        defer { isDraftingIDs.remove(message.id) }

        var text = body
        if text == nil, let provider = providerByAccount[message.accountID] {
            text = try? await provider.fetchBody(for: message)
        }
        let source = text ?? message.snippet
        var style = styleStore.load() ?? StyleProfile()
        style.aboutUser = writerProfile.summary
        // Cloud drafting only runs if the person switched it on and added their own key; the email
        // being replied to is then sent to Anthropic. Otherwise this stays on the phone.
        var services: [any AIService] = []
        if let cloud = CloudDrafts.service(onDeviceAvailable: DraftAI.onDeviceAvailable) { services.append(cloud) }
        services.append(ai)
        draftNotes[message.id] = nil
        var made: ReplyDraft?
        for service in services {
            do {
                made = try await service.draftReply(to: message, body: source, style: style)
                break
            } catch {
                if service.processingLocation == .cloud { draftNotes[message.id] = error.localizedDescription }
            }
        }
        if made == nil { made = try? await TemplateDraftService().draftReply(to: message, body: source, style: style) }
        guard let draft = made else { return nil }
        drafts[message.id] = draft
        if !usingDemoData { draftStore.save(draft) }
        return draft
    }

    /// Saves the user's edits to a draft.
    func saveDraftText(_ text: String, for message: MailMessage) {
        guard var draft = drafts[message.id], draft.body != text else { return }
        draft.body = text
        draft.status = .edited
        drafts[message.id] = draft
        if !usingDemoData { draftStore.save(draft) }
    }

    func discardDraft(for message: MailMessage) {
        drafts[message.id] = nil
        if !usingDemoData { draftStore.remove(forMessage: message.id) }
    }

    /// Learns the user's writing style from recent sent mail (on this device), at most weekly.
    func learnStyleIfNeeded(force: Bool = false) async {
        guard !usingDemoData, !sent.isEmpty else { return }
        if !force, let profile = styleStore.load(), Date().timeIntervalSince(profile.updatedAt) < 7 * 86_400 { return }
        var bodies: [String] = []
        for message in sent.prefix(15) {
            if let provider = providerByAccount[message.accountID], let body = try? await provider.fetchBody(for: message) {
                bodies.append(body)
            }
        }
        guard bodies.count >= 3 else { return }
        let profile = StyleLearner.learn(from: bodies)
        try? styleStore.save(profile)
        styleProfile = profile
    }

    /// Gets drafts ready for priority mail that is waiting on you (max 3 per refresh).
    func prepareDrafts() async {
        guard !usingDemoData else { return }
        let candidates = inboxMessages.filter { $0.awaitingReply && isPriority($0) && drafts[$0.id] == nil && !isFromMe($0) }.prefix(3)
        for message in candidates { await generateDraft(for: message) }
    }

    // MARK: Splits (your own inbox views)

    /// Your account labels seen on recent mail, most used first (offered when making a split).
    var availableLabels: [LabelCount] { SplitSuggestions.labels(in: messages) }

    func saveSplit(_ split: InboxSplit) {
        if let i = splits.firstIndex(where: { $0.id == split.id }) { splits[i] = split } else { splits.append(split) }
        try? splitStore.save(splits)
    }

    func deleteSplit(_ id: UUID) {
        splits.removeAll { $0.id == id }
        try? splitStore.save(splits)
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
        let plan = NotificationPlanner.plan(messages: inboxMessages, accounts: accounts,
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
        let held = Set(NotificationPlanner.plan(messages: inboxMessages, accounts: accounts,
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
        let text = MorningBrief.text(priorityUnread: inboxMessages.filter { !$0.isRead && isPriority($0) }.count,
                                     needsReply: inboxMessages.filter(\.awaitingReply).count,
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
