import Foundation

public struct ReplyStatus: Sendable {
    /// Inbox message ids where someone is waiting on YOU.
    public var awaitingMyReply: Set<String>
    /// Mail YOU sent that has had no answer yet (oldest wait first).
    public var awaitingTheirReply: [MailMessage]
}

/// Works out who is waiting on whom, on-device, from the inbox and sent mail.
///
/// Limitation: it only sees mail that is currently in the Inbox. If you archive their
/// reply in Gmail, a follow-up may be suggested for a thread that was answered.
public enum ReplyTracker {
    public static func analyze(inbox: [MailMessage], sent: [MailMessage], myAddresses: Set<String>,
                               now: Date = Date(), needsReplyWindowDays: Int = 14,
                               followUpAfterDays: Int = 3, followUpWindowDays: Int = 30) -> ReplyStatus {
        let me = Set(myAddresses.map { $0.lowercased() })
        func key(_ m: MailMessage) -> String { m.threadID.map { "\(m.accountID.uuidString)/\($0)" } ?? m.id }

        // Newest message from someone else, per conversation.
        var latestInbox: [String: MailMessage] = [:]
        for m in inbox where !me.contains(m.from.address.lowercased()) {
            if let current = latestInbox[key(m)], current.receivedAt >= m.receivedAt { continue }
            latestInbox[key(m)] = m
        }
        // Newest message from me, per conversation.
        var latestSent: [String: MailMessage] = [:]
        for s in sent {
            if let current = latestSent[key(s)], current.receivedAt >= s.receivedAt { continue }
            latestSent[key(s)] = s
        }

        var awaitingMine = Set<String>()
        for (k, m) in latestInbox {
            guard !m.isBulk, !BulkMailDetector.isAutomatedAddress(m.from.address),
                  !BulkMailDetector.isBroadcast(fromAddress: m.from.address, snippet: m.snippet),
                  now.timeIntervalSince(m.receivedAt) <= Double(needsReplyWindowDays) * 86_400 else { continue }
            if let mine = latestSent[k], mine.receivedAt >= m.receivedAt { continue }   // already answered
            awaitingMine.insert(m.id)
        }

        var awaitingTheirs: [MailMessage] = []
        for (k, s) in latestSent {
            let humans = s.to.filter { !BulkMailDetector.isAutomatedAddress($0.address) && !me.contains($0.address.lowercased()) }
            guard !humans.isEmpty else { continue }
            let age = now.timeIntervalSince(s.receivedAt)
            guard age >= Double(followUpAfterDays) * 86_400, age <= Double(followUpWindowDays) * 86_400 else { continue }
            if let reply = latestInbox[k], reply.receivedAt > s.receivedAt { continue }   // they answered
            awaitingTheirs.append(s)
        }
        awaitingTheirs.sort { $0.receivedAt < $1.receivedAt }
        return ReplyStatus(awaitingMyReply: awaitingMine, awaitingTheirReply: awaitingTheirs)
    }
}

/// Follow-up reminders: only for mail you sent to a PRIORITY sender, so they stay rare.
public enum FollowUpPlanner {
    public static let maxPerRun = 3
    public static let idPrefix = "followup:"

    public static func plan(awaiting: [MailMessage], accounts: [MailAccount], priority: [PrioritySender],
                            alreadyNotified: Set<String>) -> [PlannedNotification] {
        guard !priority.isEmpty else { return [] }
        let labels = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.label) })
        return awaiting
            .filter { m in !alreadyNotified.contains(idPrefix + m.id) && m.to.contains { priority.contains(address: $0.address) } }
            .prefix(maxPerRun)
            .map { m in
                let who = m.to.first { priority.contains(address: $0.address) }?.display ?? "them"
                return PlannedNotification(id: idPrefix + m.id, title: "No reply yet from \(who)",
                                           subtitle: labels[m.accountID] ?? "", body: m.subject)
            }
    }
}
