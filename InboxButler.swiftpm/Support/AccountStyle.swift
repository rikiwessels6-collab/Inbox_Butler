import SwiftUI
import InboxButlerCore

/// Visual identity for accounts: colour and icon. Lives in the app target
/// because Core has no UI dependency.
extension MailAccount {
    var badgeColor: Color {
        let palette: [Color] = [.red, .blue, .green, .orange, .purple, .teal]
        return palette[colorIndex % palette.count]
    }
}

extension AccountKind {
    var symbolName: String {
        switch self {
        case .gmail: return "envelope.fill"
        case .microsoft: return "building.2.fill"
        case .icloud: return "icloud.fill"
        case .imap: return "server.rack"
        }
    }
}
