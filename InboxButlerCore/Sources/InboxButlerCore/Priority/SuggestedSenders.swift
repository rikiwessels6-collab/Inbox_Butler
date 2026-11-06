import Foundation

public struct SenderSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { address }
    public let address: String
    public let name: String?
    public let timesWritten: Int
    /// Median minutes between their mail and your reply, if known.
    public let medianReplyMinutes: Int?

    public var reason: String {
        var text = "You've written to them \(timesWritten) times"
        if let m = medianReplyMinutes {
            text += m < 60 ? ", usually within \(max(m, 1)) min" : ", usually within \(m / 60) h"
        }
        return text + "."
    }
}

/// Suggests priority senders from your own habits (people you write to often and
/// answer quickly). Computed on-device from your sent mail.
public enum SuggestedSenders {
    public static func suggest(sent: [MailMessage], inbox: [MailMessage], existing: [PrioritySender],
                               myAddresses: Set<String>, maxCount: Int = 5) -> [SenderSuggestion] {
        let me = Set(myAddresses.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for s in sent {
            for r in s.to {
                let a = r.address.lowercased()
                guard !me.contains(a), !BulkMailDetector.isAutomatedAddress(a), !existing.contains(address: a) else { continue }
                counts[a, default: 0] += 1
                if let n = r.name, !n.isEmpty { names[a] = n }
            }
        }

        func threadKey(_ m: MailMessage) -> String { m.threadID.map { "\(m.accountID.uuidString)/\($0)" } ?? m.id }
        var delays: [String: [Int]] = [:]
        for s in sent {
            for r in s.to {
                let a = r.address.lowercased()
                guard counts[a] != nil else { continue }
                // Their latest message in this thread before my reply.
                let theirs = inbox.filter { threadKey($0) == threadKey(s) && $0.from.address.lowercased() == a && $0.receivedAt < s.receivedAt }
                if let latest = theirs.max(by: { $0.receivedAt < $1.receivedAt }) {
                    delays[a, default: []].append(Int(s.receivedAt.timeIntervalSince(latest.receivedAt) / 60))
                }
            }
        }

        func median(_ xs: [Int]) -> Int? { xs.isEmpty ? nil : xs.sorted()[xs.count / 2] }
        return counts
            .filter { $0.value >= 2 }
            .map { address, count -> (SenderSuggestion, Int) in
                let med = median(delays[address] ?? [])
                let score = count + ((med ?? Int.max) <= 240 ? 2 : 0)
                return (SenderSuggestion(address: address, name: names[address], timesWritten: count, medianReplyMinutes: med), score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.address < $1.0.address }
            .prefix(maxCount)
            .map(\.0)
    }
}
