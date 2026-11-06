import Foundation

/// Remembers proposals and their status (proposed / confirmed / dismissed), plus
/// which messages have been scanned, so nothing is proposed twice and a dismissed
/// event never returns. Local JSON, never uploaded.
public struct EventProposalStore: Sendable {
    struct FileContents: Codable {
        var proposals: [EventProposal] = []
        var scannedMessageIDs: [String] = []
    }

    private let fileURL: URL
    private let maxProposals = 500
    private let maxScanned = 2000

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("EventProposals.json")
    }

    public func all() -> [EventProposal] { read().proposals }

    public func hasScanned(_ messageID: String) -> Bool { read().scannedMessageIDs.contains(messageID) }

    /// Merges freshly found proposals with stored ones: existing ones keep their
    /// status (and any edits); new ones are added as `.proposed`. Returns the
    /// stored version of each proposal passed in, and marks the message scanned.
    @discardableResult
    public func merge(_ found: [EventProposal], forMessage messageID: String) -> [EventProposal] {
        var file = read()
        var result: [EventProposal] = []
        for proposal in found {
            if let existing = file.proposals.first(where: { $0.fingerprint == proposal.fingerprint }) {
                result.append(existing)
            } else {
                file.proposals.append(proposal)
                result.append(proposal)
            }
        }
        if !file.scannedMessageIDs.contains(messageID) { file.scannedMessageIDs.append(messageID) }
        write(file)
        return result
    }

    public func update(_ proposal: EventProposal) {
        var file = read()
        if let i = file.proposals.firstIndex(where: { $0.fingerprint == proposal.fingerprint }) {
            file.proposals[i] = proposal
        } else {
            file.proposals.append(proposal)
        }
        write(file)
    }

    /// Removes everything tied to messages of one account (used when removing the account).
    public func removeMessages(withPrefix prefix: String) {
        var file = read()
        file.proposals.removeAll { $0.sourceMessageID.hasPrefix(prefix) }
        file.scannedMessageIDs.removeAll { $0.hasPrefix(prefix) }
        write(file)
    }

    // MARK: File IO

    private func read() -> FileContents {
        guard let data = try? Data(contentsOf: fileURL) else { return FileContents() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FileContents.self, from: data)) ?? FileContents()
    }

    private func write(_ contents: FileContents) {
        var file = contents
        if file.proposals.count > maxProposals { file.proposals.removeFirst(file.proposals.count - maxProposals) }
        if file.scannedMessageIDs.count > maxScanned { file.scannedMessageIDs.removeFirst(file.scannedMessageIDs.count - maxScanned) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(file).write(to: fileURL, options: .atomic)
    }
}
