import SwiftUI

/// Shown just before Google sign-in. While the app is in Google's testing stage, Google shows an
/// "unverified app" warning, which looks alarming. This tells people exactly what to expect.
struct GoogleHeadsUpSheet: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Google").font(.serif(.title)).foregroundStyle(Theme.ink)
                Text("Google will ask you to sign in, then show a warning page. That's expected for a private app.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(1, "Sign in and pick your account.")
                step(2, "If you see \"Google hasn't verified this app\", tap Advanced, then Go to Inbox Butler.")
                step(3, "Allow read-only access to your mail. Inbox Butler can't send, delete or archive anything.")
            }
            .card(padding: 16)

            Spacer(minLength: 0)

            Button {
                dismiss()
                onContinue()
            } label: {
                Text("Continue to Google").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("google-continue")

            Button("Not now") { dismiss() }
                .font(.subheadline).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
