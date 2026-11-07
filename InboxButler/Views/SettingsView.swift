import SwiftUI
import UserNotifications
import InboxButlerCore

/// Priority senders, notification options and privacy. Only mail from priority
/// senders produces a notification.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newSender = ""
    @State private var invalidInput = false
    @State private var status: UNAuthorizationStatus = .notDetermined

    @AppStorage(AppSettings.timeSensitiveKey) private var timeSensitive = true
    @AppStorage(AppSettings.followUpsKey) private var followUps = true
    @AppStorage(AppSettings.briefKey) private var morningBrief = false
    @AppStorage(AppSettings.redactKey) private var redactWidget = false
    @AppStorage(AppSettings.lockKey) private var lockEnabled = false

    var body: some View {
        NavigationStack {
            List {
                prioritySection
                if !model.suggestions.isEmpty { suggestionsSection }
                draftingSection
                notificationsSection
                calendarSection
                privacySection
            }
            .navigationTitle("Priority & settings")
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .task { await reloadStatus() }
        }
    }

    // MARK: Sections

    private var prioritySection: some View {
        Section {
            HStack {
                TextField("name@example.com or @company.com", text: $newSender)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalidInput {
                Text("Enter a full email address, or @domain.com for everyone at a company.")
                    .font(.caption).foregroundStyle(.red)
            }
            ForEach(model.prioritySenders) { sender in
                Label(sender.pattern, systemImage: sender.isDomainRule ? "building.2" : "star.fill")
            }
            .onDelete(perform: model.removePrioritySenders)
        } header: {
            Text("Priority senders")
        } footer: {
            Text("Only mail from these senders sends a notification, and they are pinned to the top of the widget. You can also add a sender from any message.")
        }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(model.suggestions) { suggestion in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.name ?? suggestion.address).font(.headline)
                        Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add") { model.acceptSuggestion(suggestion) }
                        .buttonStyle(.borderedProminent)
                    Button { model.dismissSuggestion(suggestion) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Dismiss suggestion")
                }
            }
        } header: {
            Text("Suggested from your habits")
        } footer: {
            Text("Worked out on this device from the mail you send. Nothing changes unless you tap Add.")
        }
    }

    private var notificationsSection: some View {
        Section {
            LabeledContent("Permission", value: statusText)
            if status == .notDetermined {
                Button("Allow notifications") {
                    Task { await model.requestNotificationPermission(); await reloadStatus() }
                }
            }
            Toggle("Break through Focus (Time Sensitive)", isOn: $timeSensitive)
            Toggle("Remind me when a priority contact hasn't replied", isOn: $followUps)
            Toggle("Morning summary at 8:00", isOn: $morningBrief)
                .onChange(of: morningBrief) { _, _ in Task { await model.rescheduleBrief() } }
            Button("Send a test notification") {
                Task { await model.sendTestNotification() }
            }
            .disabled(status != .authorized)
        } header: {
            Text("Notifications")
        } footer: {
            Text("A notification shows the sender and subject. It is created on this device from mail already downloaded; nothing is sent to any server. New mail is checked when iOS allows background refresh (usually every 15 minutes or more), so alerts are not instant. Follow-up reminders need the original reply to still be in your Inbox to be accurate.")
        }
    }

    private var draftingSection: some View {
        Section {
            Text(model.aiStatusText).font(.footnote)
            if let style = model.styleProfile {
                LabeledContent("Learned from", value: "\(style.sampleCount) sent emails")
                if let g = style.greetings.first { LabeledContent("Greeting", value: g) }
                if let s = style.signOffs.first { LabeledContent("Sign-off", value: s) }
            } else {
                Text("Your writing style is learned from your sent mail after the first sync.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Learn my style again") { Task { await model.learnStyleIfNeeded(force: true) } }
        } header: {
            Text("Reply drafts")
        } footer: {
            Text("Drafts and your writing style are created and stored on this device only. Nothing is sent anywhere to write them, and a reply is only sent when you tap Send in the mail sheet.")
        }
    }

    private var calendarSection: some View {
        Section {
            LabeledContent("Calendar access", value: calendarStatusText)
            if model.calendarAccess != .granted {
                Button("Allow calendar access") { Task { await model.requestCalendarAccess() } }
            }
            ForEach(model.calendars) { calendar in
                Label(calendar.displayName, systemImage: calendar.id == model.targetCalendarID ? "checkmark.circle.fill" : "calendar")
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Full access lets you choose which calendar (iCloud, family, Google) each event goes to, and shows overlaps. The app only looks at events around the time of the one you're adding; nothing from your calendar is stored or sent anywhere. To use Google calendars, add your Google account in iOS Settings > Calendar > Accounts and switch Calendars on. Events then sync to Google automatically.")
        }
        .task { await model.refreshCalendars() }
    }

    private var calendarStatusText: String {
        switch model.calendarAccess {
        case .granted: return "On"
        case .denied: return "Off (enable in Settings)"
        case .notDetermined: return "Not asked yet"
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Hide sender and subject on widgets", isOn: $redactWidget)
                .onChange(of: redactWidget) { _, _ in model.publishWidgetSnapshot() }
            Toggle("Require Face ID to open the app", isOn: $lockEnabled)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Widgets on the Lock Screen can be seen without unlocking your phone. Hiding details shows counts only.")
        }
    }

    // MARK: Helpers

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off (enable in Settings)"
        default: return "Not asked yet"
        }
    }

    private func reloadStatus() async { status = await model.notificationStatus() }

    private func add() {
        invalidInput = !model.addPrioritySender(newSender)
        if !invalidInput { newSender = "" }
    }
}
