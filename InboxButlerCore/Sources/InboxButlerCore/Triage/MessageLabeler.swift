import Foundation

public struct MessageLabel: Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case security, invoice, receipt, travel, appointment, meeting, delivery, toReview, newsletter
    }
    public let kind: Kind
    public var id: String { kind.rawValue }

    public var title: String {
        switch kind {
        case .security: return "Security"
        case .invoice: return "Invoice"
        case .receipt: return "Receipt"
        case .travel: return "Travel"
        case .appointment: return "Appointment"
        case .meeting: return "Meeting"
        case .delivery: return "Delivery"
        case .toReview: return "To review"
        case .newsletter: return "Newsletter"
        }
    }
}

/// Quick on-device labels for the inbox list. Simple keyword rules over the subject, preview
/// and attachments: instant, works offline, and nothing leaves the device.
public enum MessageLabeler {
    private static let rules: [(MessageLabel.Kind, [String])] = [
        (.security, ["verification code", "security code", "one-time", "sign-in", "sign in attempt", "login attempt", "password reset", "reset your password", "2fa", "suspicious"]),
        (.invoice, ["invoice", "amount due", "payment due", "payment reminder", "statement", "overdue", "bill for"]),
        (.receipt, ["receipt", "order confirmation", "your order", "thanks for your purchase", "payment received", "payment confirmation"]),
        (.travel, ["flight", "itinerary", "boarding", "check-in", "e-ticket", "booking reference", "hotel", "reservation confirmed"]),
        (.appointment, ["appointment", "booking confirmed", "booked for", "your visit", "reschedul", "confirmed for"]),
        (.meeting, ["meeting", "invitation", "invite", "webinar", "zoom", "teams meeting", "agenda", "calendar"]),
        (.delivery, ["shipped", "tracking", "out for delivery", "delivered", "parcel", "dispatched", "your package"]),
        (.toReview, ["please review", "for your review", "for approval", "please find attached", "attached is", "please sign"])
    ]

    public static func labels(for message: MailMessage, body: String? = nil, max: Int = 2) -> [MessageLabel] {
        let text = (message.subject + " " + message.snippet + " " + (body.map { String($0.prefix(600)) } ?? "")).lowercased()
        var found: [MessageLabel.Kind] = []
        for (kind, words) in rules where words.contains(where: { text.contains($0) }) { found.append(kind) }

        if message.attachments.contains(where: { $0.kind == .calendar }), !found.contains(.meeting) { found.append(.meeting) }
        if !message.isBulk, message.attachments.contains(where: { $0.kind == .pdf || $0.kind == .wordDocument }),
           !found.contains(.toReview), !found.contains(.invoice), !found.contains(.receipt) { found.append(.toReview) }
        // Mailing-list mail is a newsletter unless something more specific matched.
        if message.isBulk, !found.contains(.receipt), !found.contains(.delivery), !found.contains(.security) { found.append(.newsletter) }

        return Array(found.prefix(max)).map { MessageLabel(kind: $0) }
    }
}
