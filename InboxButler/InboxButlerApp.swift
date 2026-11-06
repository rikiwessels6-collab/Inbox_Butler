import SwiftUI

/// App entry point. One shared `AppModel` is injected into the environment.
@main
struct InboxButlerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .task { await AppModel.shared.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        // iOS wakes the app here (at its discretion) to check for new mail.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()   // chain the next wake-up
            await AppModel.shared.refresh()
        }
    }
}
