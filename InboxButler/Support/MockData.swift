import Foundation
import InboxButlerCore

/// Fake accounts and mail so the UI works before any provider is connected.
enum MockData {
    static func make() -> (accounts: [MailAccount], providers: [any MailProvider]) {
        let gmail = MailAccount(kind: .gmail, emailAddress: "me@gmail.com", label: "Personal", colorIndex: 0)
        let work = MailAccount(kind: .microsoft, emailAddress: "me@outlook.com", label: "Work", colorIndex: 1)
        let icloud = MailAccount(kind: .icloud, emailAddress: "me@icloud.com", label: "iCloud", colorIndex: 2)
        let other = MailAccount(kind: .imap, emailAddress: "me@example.org", label: "Club", colorIndex: 3)

        func m(_ acc: MailAccount, _ id: String, _ from: String, _ subject: String, _ snippet: String,
               hoursAgo: Double, read: Bool = false, importance: Double? = nil,
               waiting: Bool = false, attachments: [AttachmentInfo] = []) -> MailMessage {
            MailMessage(accountID: acc.id, providerMessageID: id,
                        from: MailAddress(name: from, address: "\(from.lowercased().replacingOccurrences(of: " ", with: "."))@example.com"),
                        to: [MailAddress(address: acc.emailAddress)],
                        subject: subject, snippet: snippet,
                        receivedAt: Date(timeIntervalSinceNow: -hoursAgo * 3600),
                        isRead: read, attachments: attachments, importance: importance,
                        awaitingReply: waiting)
        }
        let pdf = AttachmentInfo(id: "a1", filename: "Invoice-1042.pdf", mimeType: "application/pdf", byteCount: 84_000, kind: .pdf)
        let ics = AttachmentInfo(id: "a2", filename: "invite.ics", mimeType: "text/calendar", byteCount: 1_200, kind: .calendar)

        // Tomorrow at 14:30 (device time zone), as text and as a calendar file.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let longDate = DateFormatter(); longDate.locale = Locale(identifier: "en_US_POSIX"); longDate.dateFormat = "MMMM d, yyyy"
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd"
        let ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Appointment at Dr Patel's Surgery\nDTSTART:\(stamp.string(from: tomorrow))T143000\nDTEND:\(stamp.string(from: tomorrow))T150000\nLOCATION:12 High Street\nEND:VEVENT\nEND:VCALENDAR"
        let gmailBodies = ["g1": "Hello,\nYour appointment is confirmed for \(longDate.string(from: tomorrow)) at 2:30 PM.\nPlease arrive 10 minutes early.\nThe attached invite has the details."]

        let providers: [any MailProvider] = [
            MockMailProvider(account: gmail, messages: [
                m(gmail, "g1", "Dr Patel's Surgery", "Appointment confirmed Thu 14:30", "Your appointment is booked for Thursday at 14:30.", hoursAgo: 0.5, importance: 0.8, attachments: [ics]),
                m(gmail, "g2", "Mum", "Sunday lunch?", "Are you coming on Sunday? Let me know by Friday.", hoursAgo: 5, importance: 0.5, waiting: true)
            ], bodies: gmailBodies, attachmentData: ["a2": Data(ics.utf8)]),
            MockMailProvider(account: work, messages: [
                m(work, "w1", "Sam Rivera", "Contract needs signing today", "Please review and sign before 17:00.", hoursAgo: 1, importance: 0.95, waiting: true, attachments: [pdf]),
                m(work, "w2", "Team Calendar", "Weekly sync moved to Wed", "The weekly sync is now on Wednesday at 10:00.", hoursAgo: 8, read: true)
            ]),
            MockMailProvider(account: icloud, messages: [
                m(icloud, "i1", "Apple", "Your receipt", "Thanks for your purchase.", hoursAgo: 26, read: true, importance: 0.1)
            ]),
            MockMailProvider(account: other, messages: [
                m(other, "o1", "Chess Club", "Tournament dates announced", "The spring tournament runs 12 to 14 April.", hoursAgo: 3, importance: 0.4)
            ])
        ]
        return ([gmail, work, icloud, other], providers)
    }
}
