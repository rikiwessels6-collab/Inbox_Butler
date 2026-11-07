import SwiftUI
import InboxButlerCore

/// Small pill showing which account a message belongs to.
struct AccountBadge: View {
    let account: MailAccount

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(account.badgeColor).frame(width: 6, height: 6)
            Text(account.label).font(.caption.weight(.medium)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.hairline.opacity(0.7), in: Capsule())
        .accessibilityLabel("Account \(account.label)")
    }
}
