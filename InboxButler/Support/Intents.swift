import AppIntents
import InboxButlerCore

/// "Hey Siri, what's urgent in Inbox Butler?" Reads the same small summary as the
/// widget, so it never opens the mailbox itself.
struct WhatsUrgentIntent: AppIntent {
    static var title: LocalizedStringResource = "What's urgent?"
    static var description = IntentDescription("Tells you your priority mail, replies waiting and today's events.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = WidgetSnapshotStore().load()?.spokenSummary
            ?? "Open Inbox Butler once so I can check your mail."
        return .result(dialog: "\(text)")
    }
}

struct InboxButlerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsUrgentIntent(),
                    phrases: ["What's urgent in \(.applicationName)", "Check \(.applicationName)"],
                    shortTitle: "What's urgent",
                    systemImageName: "star.circle")
    }
}
