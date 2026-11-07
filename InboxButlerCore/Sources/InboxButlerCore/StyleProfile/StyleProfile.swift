import Foundation

/// How the user writes, learned ON-DEVICE from their sent mail. Stored locally;
/// never uploaded. It describes habits, it does not copy whole emails.
public struct StyleProfile: Codable, Hashable, Sendable {
    public var greetings: [String]          // "Hi {name},", "Hello,"
    public var signOffs: [String]           // "Cheers,", "Kind regards,"
    public var averageSentenceWords: Double
    public var formality: Double            // 0 casual ... 1 formal
    public var usesEmoji: Bool
    public var commonPhrases: [String]
    public var sampleCount: Int             // sent messages analysed
    /// A few of the user's own short replies, used as examples when drafting (on-device only).
    public var exampleReplies: [String]
    /// Optional one-liner about the user (from `WriterProfile`), added when drafting.
    public var aboutUser: String
    public var updatedAt: Date

    public init(greetings: [String] = [], signOffs: [String] = [], averageSentenceWords: Double = 0,
                formality: Double = 0.5, usesEmoji: Bool = false, commonPhrases: [String] = [],
                sampleCount: Int = 0, exampleReplies: [String] = [], aboutUser: String = "", updatedAt: Date = Date()) {
        self.greetings = greetings
        self.signOffs = signOffs
        self.averageSentenceWords = averageSentenceWords
        self.formality = formality
        self.usesEmoji = usesEmoji
        self.commonPhrases = commonPhrases
        self.sampleCount = sampleCount
        self.exampleReplies = exampleReplies
        self.aboutUser = aboutUser
        self.updatedAt = updatedAt
    }
}

/// Saves the profile as a JSON file in the app's Application Support folder.
public struct StyleProfileStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("StyleProfile.json")
    }

    public func load() -> StyleProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StyleProfile.self, from: data)
    }

    public func save(_ profile: StyleProfile) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(profile).write(to: fileURL, options: .atomic)
    }

    public func delete() { try? FileManager.default.removeItem(at: fileURL) }
}
