import SwiftUI

/// Tab layout: unified inbox first, accounts second, priority and settings third.
/// Covered by a lock screen when the optional Face ID lock is on.
struct RootView: View {
    @Environment(\.scenePhase) private var phase
    @State private var lock = AppLock.shared

    var body: some View {
        ZStack {
            TabView {
                UnifiedInboxView()
                    .tabItem { Label("Inbox", systemImage: "tray.full") }
                AccountListView()
                    .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                SettingsView()
                    .tabItem { Label("Priority", systemImage: "star.circle") }
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
