import SwiftUI
import InboxButlerCore

/// Visual identity for accounts: colour and icon. Lives in the app target
/// because Core has no UI dependency.
extension MailAccount {
    var badgeColor: Color { Theme.palette[colorIndex % Theme.palette.count] }
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

extension AttachmentInfo.Kind {
    var symbolName: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .calendar: return "calendar"
        case .wordDocument: return "doc.text"
        case .other: return "doc"
        }
    }
}

extension MessageLabel {
    /// Colour and icon for each automatic label.
    var tint: Color {
        switch kind {
        case .security: return Color(hex: 0xC2476B)
        case .invoice: return Theme.gold
        case .receipt: return Color(hex: 0x1F9D8F)
        case .travel: return Color(hex: 0x3E7BD1)
        case .appointment: return Theme.accent
        case .meeting: return Color(hex: 0x8A63D2)
        case .delivery: return Theme.warn
        case .toReview: return Color(hex: 0x4F6B8A)
        case .newsletter: return Theme.muted
        }
    }

    var symbolName: String {
        switch kind {
        case .security: return "lock.shield"
        case .invoice: return "doc.text"
        case .receipt: return "receipt"
        case .travel: return "airplane"
        case .appointment: return "calendar"
        case .meeting: return "person.2"
        case .delivery: return "shippingbox"
        case .toReview: return "eye"
        case .newsletter: return "newspaper"
        }
    }
}
