import SwiftUI
import InboxButlerCore

/// Small coloured capsule showing which account a message belongs to.
struct AccountBadge: View {
    let account: MailAccount

    var body: some View {
        Text(account.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(account.badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(account.badgeColor)
            .accessibilityLabel("Account \(account.label)")
    }
}
