import UserNotifications
import InboxButlerCore

/// Posts LOCAL notifications (generated on the device from already-downloaded
/// mail). Nothing is sent to a push server, and nothing about the mail leaves
/// the device to produce them.
struct NotificationService {
    private var center: UNUserNotificationCenter { .current() }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Shows: title = sender, subtitle = account, body = subject.
    /// `urgent` notifications (priority senders) are Time Sensitive when enabled, so they
    /// can break through a Focus mode; everything else is a normal notification.
    func post(_ n: PlannedNotification, urgent: Bool = true) async {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.subtitle = n.subtitle
        content.body = n.body
        content.sound = .default
        if urgent && AppSettings.bool(AppSettings.timeSensitiveKey, default: true) {
            content.interruptionLevel = .timeSensitive
        }
        content.threadIdentifier = n.subtitle          // groups by account
        content.userInfo = ["messageID": n.id]
        let request = UNNotificationRequest(identifier: n.id, content: content, trigger: nil)
        try? await center.add(request)
    }
}

extension NotificationService {
    /// A local notification when a "Remind me" comes due.
    func scheduleReminder(id: String, title: String, subtitle: String, body: String, at date: Date) async {
        guard date > Date(), await status() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = ["messageID": id]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "reminder:" + id, content: content, trigger: trigger))
    }

    func cancelReminder(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder:" + id])
    }
}

extension NotificationService {
    private static let briefID = "morning-brief"

    func cancelMorningBrief() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.briefID])
    }

    /// Replaces the pending brief with one that fires once at `date`.
    func scheduleMorningBrief(at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.briefID])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.briefID, content: content, trigger: trigger))
    }
}

/// Without this, iOS hides notifications while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
