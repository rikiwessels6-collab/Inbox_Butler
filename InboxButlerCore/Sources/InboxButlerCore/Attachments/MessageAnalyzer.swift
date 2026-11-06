import Foundation

public struct MessageAnalysis: Sendable {
    public var body: String
    public var proposals: [EventProposal]
    /// Human-readable problems, e.g. "scan.pdf is too large to scan."
    public var notes: [String]
}

/// Reads a message's text and attachments ON-DEVICE and proposes events.
/// Attachments are downloaded from the user's own mail server, scanned in memory
/// and discarded; nothing is sent anywhere else.
public struct MessageAnalyzer: Sendable {
    public static let maxAttachments = 5
    private let extractor: AttachmentTextExtractor

    public init(extractor: AttachmentTextExtractor = AttachmentTextExtractor()) {
        self.extractor = extractor
    }

    public func analyze(_ message: MailMessage, provider: any MailProvider,
                        referenceDate: Date = Date()) async -> MessageAnalysis {
        var notes: [String] = []
        var body: String
        do {
            body = try await provider.fetchBody(for: message)
        } catch {
            body = message.snippet
            notes.append("Couldn't load the full message: \(error.localizedDescription)")
        }

        var proposals = DateEventExtractor.events(in: message.subject + "\n" + body,
                                                  sourceMessageID: message.id, referenceDate: referenceDate)

        for attachment in message.attachments.prefix(Self.maxAttachments) where attachment.kind != .other {
            if attachment.byteCount > AttachmentTextExtractor.maxBytes {
                notes.append("\(attachment.filename) is too large to scan.")
                continue
            }
            do {
                let data = try await provider.fetchAttachment(attachment, in: message)
                if attachment.kind == .calendar {
                    proposals += ICSParser.events(from: String(decoding: data, as: UTF8.self),
                                                  sourceMessageID: message.id, referenceDate: referenceDate,
                                                  filename: attachment.filename)
                } else {
                    let text = try await extractor.text(from: data, kind: attachment.kind, filename: attachment.filename)
                    proposals += DateEventExtractor.events(in: text, sourceMessageID: message.id,
                                                           source: .attachmentText, fileLabel: attachment.filename,
                                                           referenceDate: referenceDate)
                }
            } catch {
                notes.append("\(attachment.filename) \(error.localizedDescription)")
            }
        }

        // One proposal per fingerprint (a calendar file beats text found in the body), soonest first.
        var seen = Set<String>()
        let unique = proposals
            .sorted { ($0.source == .calendarFile ? 0 : 1) < ($1.source == .calendarFile ? 0 : 1) }
            .filter { seen.insert($0.fingerprint).inserted }
            .sorted { $0.start < $1.start }
        return MessageAnalysis(body: body, proposals: unique, notes: notes)
    }
}
