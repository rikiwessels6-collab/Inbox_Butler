import BackgroundTasks

/// Asks iOS to wake the app now and then to check for new mail.
/// iOS decides when (typically 15+ minutes, less often if the app is rarely
/// used or Low Power Mode is on), so this is NOT real-time. Real-time needs a
/// push server; see ARCHITECTURE.md.
enum BackgroundRefresh {
    /// Must match BGTaskSchedulerPermittedIdentifiers in project.yml.
    static let identifier = "com.example.InboxButler.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
