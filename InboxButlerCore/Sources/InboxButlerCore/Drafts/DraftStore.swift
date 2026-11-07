import Foundation

/// Reply drafts kept on the device (local JSON). Drafts are never sent from here.
public struct DraftStore: Sendable {
    private let fileURL: URL
    private let maxDrafts = 200

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("Drafts.json")
    }

    public func all() -> [ReplyDraft] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ReplyDraft].self, from: data)) ?? []
    }

    /// Saves a draft, replacing any earlier draft for the same message.
    public func save(_ draft: ReplyDraft) {
        var drafts = all().filter { $0.inReplyToMessageID != draft.inReplyToMessageID }
        drafts.append(draft)
        write(drafts)
    }

    public func remove(forMessage messageID: String) {
        write(all().filter { $0.inReplyToMessageID != messageID })
    }

    /// Removes all drafts for one account's messages (used when removing the account).
    public func removeMessages(withPrefix prefix: String) {
        write(all().filter { !$0.inReplyToMessageID.hasPrefix(prefix) })
    }

    private func write(_ drafts: [ReplyDraft]) {
        let kept = drafts.count > maxDrafts ? Array(drafts.suffix(maxDrafts)) : drafts
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(kept).write(to: fileURL, options: .atomic)
    }
}
