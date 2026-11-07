import Foundation

/// A few lines about the user ("Cricket umpire at Cricket Australia") that help drafts sound
/// like them. Optional, stored on this device only.
public struct WriterProfile: Codable, Equatable, Sendable {
    public var jobTitle: String
    public var organisation: String
    public var about: String

    public init(jobTitle: String = "", organisation: String = "", about: String = "") {
        self.jobTitle = jobTitle; self.organisation = organisation; self.about = about
    }

    public var isEmpty: Bool {
        [jobTitle, organisation, about].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// One sentence for the AI prompt, e.g. "The user is a Cricket umpire at Cricket Australia. ..."
    public var summary: String {
        var parts: [String] = []
        let title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let org = organisation.trimmingCharacters(in: .whitespacesAndNewlines)
        let more = about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && !org.isEmpty { parts.append("The user is \(title) at \(org).") }
        else if !title.isEmpty { parts.append("The user's role: \(title).") }
        else if !org.isEmpty { parts.append("The user works at \(org).") }
        if !more.isEmpty { parts.append(more) }
        return parts.joined(separator: " ")
    }
}

public struct WriterProfileStore: Sendable {
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("WriterProfile.json")
    }

    public func load() -> WriterProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WriterProfile.self, from: data)
    }

    public func save(_ profile: WriterProfile) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(profile).write(to: fileURL, options: .atomic)
    }
}
