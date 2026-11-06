import SwiftUI

/// Tab layout: unified inbox first, accounts second.
struct RootView: View {
    var body: some View {
        TabView {
            UnifiedInboxView()
                .tabItem { Label("Inbox", systemImage: "tray.full") }
            AccountListView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
        }
    }
}
