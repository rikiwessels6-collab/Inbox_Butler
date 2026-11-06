import Foundation

/// Which kind of mailbox an account is. Decides which `MailProvider` handles it.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case gmail
    case microsoft   // Outlook / Hotmail / Live
    case icloud      // IMAP + app-specific password
    case imap        // any other IMAP server

    public var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .microsoft: return "Outlook / Hotmail"
        case .icloud: return "iCloud"
        case .imap: return "IMAP"
        }
    }
}

/// A connected mailbox. Contains NO secrets: tokens and passwords live in the
/// Keychain, looked up with `id` (see `KeychainStore`).
public struct MailAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: AccountKind
    public var emailAddress: String
    /// Short label shown in the account badge, e.g. "Work".
    public var label: String
    /// Index into the app's badge colour palette.
    public var colorIndex: Int

    public init(id: UUID = UUID(), kind: AccountKind, emailAddress: String,
                label: String, colorIndex: Int) {
        self.id = id
        self.kind = kind
        self.emailAddress = emailAddress
        self.label = label
        self.colorIndex = colorIndex
    }
}
