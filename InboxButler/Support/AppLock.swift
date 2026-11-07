import SwiftUI
import LocalAuthentication

/// Optional Face ID / Touch ID / passcode lock. When on, the app locks each time it
/// goes to the background and hides its contents in the app switcher.
@Observable
@MainActor
final class AppLock {
    static let shared = AppLock()

    private(set) var isLocked: Bool
    private var isAuthenticating = false

    private init() { isLocked = AppSettings.bool(AppSettings.lockKey, default: false) }

    var isEnabled: Bool { AppSettings.bool(AppSettings.lockKey, default: false) }

    func lockIfEnabled() { if isEnabled { isLocked = true } }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        // No passcode set on the device: nothing to check against, so don't trap the user out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { isLocked = false; return }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                              localizedReason: "Unlock Inbox Butler")) == true {
            isLocked = false
        }
    }
}

struct LockOverlay: View {
    let unlock: () -> Void
    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Inbox Butler is locked").font(.headline)
                Button("Unlock", action: unlock).buttonStyle(.borderedProminent)
            }
        }
        .accessibilityAddTraits(.isModal)   // VoiceOver can't read the mail behind the lock
    }
}
