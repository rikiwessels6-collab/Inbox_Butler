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
    func post(_ n: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.subtitle = n.subtitle
        content.body = n.body
        content.sound = .default
        content.threadIdentifier = n.subtitle          // groups by account
        content.userInfo = ["messageID": n.id]
        let request = UNNotificationRequest(identifier: n.id, content: content, trigger: nil)
        try? await center.add(request)
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
