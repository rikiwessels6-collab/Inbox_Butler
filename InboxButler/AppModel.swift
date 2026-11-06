import SwiftUI
import InboxButlerCore
import WidgetKit

/// Holds app-wide state for the UI: accounts, the merged inbox, sync errors.
/// Uses mock providers for now; real providers replace them one at a time.
@Observable
@MainActor
final class AppModel {
    private(set) var accounts: [MailAccount] = []
    private(set) var messages: [MailMessage] = []
    private(set) var errors: [UUID: String] = [:]
    private(set) var isRefreshing = false

    private var providers: [any MailProvider] = []
    private var engine = SyncEngine(providers: [])

    init() {
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
    }

    /// Writes the small summary the widget reads (App Group file) and asks
    /// WidgetKit to refresh. Contains sender/subject text; see README privacy notes.
    private func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot.make(messages: messages, accounts: accounts)
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
