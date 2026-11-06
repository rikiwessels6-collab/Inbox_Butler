import SwiftUI

/// App entry point. A single `AppModel` is created once and shared via the
/// environment.
@main
struct InboxButlerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.refresh() }
        }
    }
}
