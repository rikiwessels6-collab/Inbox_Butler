import SwiftUI

enum AppTab: Hashable { case inbox, accounts, priority }

/// Lets any screen switch tabs (e.g. the demo banner's "Connect an account").
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var tab: AppTab = .inbox
    private init() {}
}

/// Tab layout: inbox, accounts, priority and settings. Covered by a lock screen
/// when the optional Face ID lock is on.
struct RootView: View {
    @Environment(\.scenePhase) private var phase
    @State private var lock = AppLock.shared
    @Bindable private var router = AppRouter.shared
    @Environment(AppModel.self) private var model
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                UnifiedInboxView()
                    .tabItem { Label("Inbox", systemImage: "tray.full") }
                    .tag(AppTab.inbox)
                AccountListView()
                    .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                    .tag(AppTab.accounts)
                SettingsView()
                    .tabItem { Label("Priority", systemImage: "star.circle") }
                    .tag(AppTab.priority)
            }
            if !hasSeenWelcome && model.usingDemoData {
                WelcomeView { withAnimation(.easeInOut(duration: 0.5)) { hasSeenWelcome = true } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            // Also covers the app-switcher snapshot (phase is .inactive while it is taken).
            if lock.isLocked || (lock.isEnabled && phase != .active) {
                LockOverlay { Task { await lock.unlock() } }
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .background { lock.lockIfEnabled() }
            if newPhase == .active { Task { await lock.unlock() } }
        }
        .task { await lock.unlock() }
    }
}
