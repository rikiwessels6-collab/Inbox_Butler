import SwiftUI
import InboxButlerCore
import WidgetKit
import UserNotifications

/// Holds app-wide state for the UI: accounts, the merged inbox, sync errors.
/// Uses mock providers for now; real providers replace them one at a time.
@Observable
@MainActor
final class AppModel {
    /// Single shared instance (also used by the background refresh task).
    static let shared = AppModel()

    private(set) var prioritySenders: [PrioritySender] = []
    private(set) var accounts: [MailAccount] = []
    private(set) var messages: [MailMessage] = []
    private(set) var errors: [UUID: String] = [:]
    private(set) var isRefreshing = false

    private var providers: [any MailProvider] = []
    private var engine = SyncEngine(providers: [])

    private let senderStore = PrioritySenderStore()
    private let notifiedStore = NotifiedStore()
    private let notifier = NotificationService()

    private init() {
        prioritySenders = senderStore.load()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        let mock = MockData.make()
        accounts = mock.accounts
        providers = mock.providers
        engine = SyncEngine(providers: providers)
    }

    func account(for id: UUID) -> MailAccount? {
        accounts.first { $0.id == id }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let result = await engine.refresh()
        messages = result.messages
        errors = result.errors
        publishWidgetSnapshot()
        await notifyForNewMail()
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

    func notificationStatus() async -> UNAuthorizationStatus { await notifier.status() }
    func requestNotificationPermission() async { await notifier.requestAuthorization() }

    /// Lets the user see exactly what a priority notification looks like.
    func sendTestNotification() async {
        await notifier.post(PlannedNotification(id: "test-\(UUID().uuidString)", title: "Sam Rivera",
                                                subtitle: "Work", body: "Contract needs signing today"))
    }

    /// Writes the small summary the widget reads (App Group file) and asks
    /// WidgetKit to refresh. Contains sender/subject text; see README privacy notes.
    private func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot.make(messages: messages, accounts: accounts, priority: prioritySenders)
        if WidgetSnapshotStore().save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Local-only: marks read in the app. Never changes the real mailbox.
    func markReadLocally(_ message: MailMessage) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].isRead = true
    }
}
