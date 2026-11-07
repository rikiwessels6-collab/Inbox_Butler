import SwiftUI

/// The "inbox zero" reward: a landscape with a quiet message, instead of an empty list.
struct CaughtUpCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WelcomeBackdrop()
                .frame(height: 300)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text("You're all caught up")
                    .font(.serif(.title))
                    .foregroundStyle(Color.white)
                Text("Nothing needs you right now. Enjoy the quiet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(22)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all caught up. Nothing needs you right now.")
    }
}
