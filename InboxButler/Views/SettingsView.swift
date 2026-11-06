import SwiftUI
import UserNotifications
import InboxButlerCore

/// Priority senders + notification settings. Only mail from senders listed here
/// produces a notification.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newSender = ""
    @State private var invalidInput = false
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            List {
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

                Section {
                    LabeledContent("Permission", value: statusText)
                    if status == .notDetermined {
                        Button("Allow notifications") {
                            Task { await model.requestNotificationPermission(); await reloadStatus() }
                        }
                    }
                    Button("Send a test notification") {
                        Task { await model.sendTestNotification() }
                    }
                    .disabled(status != .authorized)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("A notification shows the sender and subject. It is created on this device from mail already downloaded; nothing is sent to any server. New mail is checked when iOS allows background refresh (usually every 15 minutes or more), so alerts are not instant.")
                }
            }
            .navigationTitle("Priority")
            .task { await reloadStatus() }
        }
    }

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
