import SwiftUI

enum AppTab: Hashable { case calendar, inbox, settings }

/// Lets any screen switch tabs (e.g. the demo banner's "Connect an account").
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()
    var tab: AppTab = .calendar
    var showsAccounts = false
    var showsActions = false

    func openAccounts() {
        showsActions = false
        tab = .settings
        showsAccounts = true
    }
    private init() {}
}

/// Main navigation and onboarding. Covered by a lock screen
/// when the optional Face ID lock is on.
struct RootView: View {
    @Environment(\.scenePhase) private var phase
    @State private var lock = AppLock.shared
    @Bindable private var router = AppRouter.shared
    @Environment(AppModel.self) private var model
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasSeenTour") private var hasSeenTour = false

    private var welcomeShowing: Bool { !hasSeenWelcome && model.usingDemoData }
    private var tourShowing: Bool { hasSeenWelcome && !hasSeenTour }
    private var lockShowing: Bool { lock.isLocked || (lock.isEnabled && phase != .active) }

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                CalendarTabView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(AppTab.calendar)
                UnifiedInboxView()
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .tag(AppTab.inbox)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            // While a full-screen overlay (welcome, tour, lock) is on top, the app underneath must
            // not be reachable by VoiceOver or other assistive tools.
            .accessibilityHidden(welcomeShowing || tourShowing || lockShowing)
            if welcomeShowing {
                WelcomeView { withAnimation(.easeInOut(duration: 0.5)) { hasSeenWelcome = true } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if tourShowing {
                OnboardingTourView { withAnimation(.easeInOut(duration: 0.5)) { hasSeenTour = true } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            // Also covers the app-switcher snapshot (phase is .inactive while it is taken).
            if lockShowing {
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
