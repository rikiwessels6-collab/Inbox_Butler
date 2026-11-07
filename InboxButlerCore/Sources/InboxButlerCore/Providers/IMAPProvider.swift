import Foundation

/// Where and how to sign in to an IMAP server. Stored in the Keychain, never on disk.
public struct IMAPCredentials: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String

    public init(host: String, port: Int = 993, username: String, password: String) {
        self.host = host; self.port = port; self.username = username; self.password = password
    }

    /// iCloud Mail: sign in with the Apple ID email and an APP-SPECIFIC password
    /// (created at appleid.apple.com), never the real Apple ID password.
    public static func icloud(email: String, appPassword: String) -> IMAPCredentials {
        IMAPCredentials(host: "imap.mail.me.com", port: 993, username: email, password: appPassword)
    }
}

/// iCloud and generic IMAP mail over TLS, strictly READ-ONLY (see `IMAPClient`).
public struct IMAPProvider: MailProvider {
    public let account: MailAccount
    private let secrets: SecretStore
    private let transportFactory: @Sendable () -> any IMAPTransport

    public init(account: MailAccount, secrets: SecretStore = KeychainStore()) {
        self.init(account: account, secrets: secrets, transportFactory: { NWIMAPTransport() })
    }

    init(account: MailAccount, secrets: SecretStore, transportFactory: @escaping @Sendable () -> any IMAPTransport) {
        self.account = account
        self.secrets = secrets
        self.transportFactory = transportFactory
    }

    public static func keychainKey(for accountID: UUID) -> String { "\(accountID.uuidString).imap" }

    public static func save(_ credentials: IMAPCredentials, for accountID: UUID, in secrets: SecretStore) throws {
        let data = try JSONEncoder().encode(credentials)
        try secrets.set(String(decoding: data, as: UTF8.self), for: keychainKey(for: accountID))
    }

    public static func removeCredentials(for accountID: UUID, from secrets: SecretStore) {
        secrets.remove(keychainKey(for: accountID))
    }

    /// Signs in once to check the credentials work. Used when adding an account.
    public static func verify(_ credentials: IMAPCredentials) async throws {
        try await verify(credentials, transportFactory: { NWIMAPTransport() })
    }

    static func verify(_ credentials: IMAPCredentials,
                       transportFactory: @escaping @Sendable () -> any IMAPTransport) async throws {
        _ = try await withSession(credentials: credentials, transportFactory: transportFactory) { client in
            try await client.listMailboxes()
        }
    }

    // MARK: MailProvider

    public func authorize() async throws {
        _ = try await session { try await $0.listMailboxes() }
    }

    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        try await session { client in
            guard let name = try await resolve(mailbox, using: client) else { return MailPage(messages: []) }
            let exists = try await client.examine(name)
            guard exists > 0 else { return MailPage(messages: []) }
            let start = max(1, exists - max(limit, 1) + 1)
            let fetched = try await client.fetch(range: "\(start):\(exists)", items: Self.listItems)

            var messages: [MailMessage] = []
            for item in fetched {
                guard let uid = item.uid else { continue }
                var snippet = ""
                if mailbox == .inbox, let part = Self.textParts(item.parts).plain ?? Self.textParts(item.parts).html {
                    // Best effort: a short peek at the text for the list preview.
                    if let peek = try? await client.uidFetch(uid: uid, items: "BODY.PEEK[\(part.number)]<0.600>"),
                       let bytes = peek.section(prefix: "BODY[\(part.number)]") {
                        snippet = Self.snippet(from: bytes, part: part)
                    }
                }
                messages.append(Self.convert(item, uid: uid, mailbox: mailbox, snippet: snippet, accountID: account.id))
            }
            messages.sort { $0.receivedAt > $1.receivedAt }
            return MailPage(messages: messages, nextCursor: nil)
        }
    }

    public func fetchBody(for message: MailMessage) async throws -> String {
        try await withMessage(message) { client, uid in
            guard let structure = try await client.uidFetch(uid: uid, items: "BODYSTRUCTURE") else { return message.snippet }
            let text = Self.textParts(structure.parts)
            if let plain = text.plain, let body = try await Self.fetchPart(plain, uid: uid, client: client) { return body }
            if let html = text.html, let body = try await Self.fetchPart(html, uid: uid, client: client) { return HTMLText.strip(body) }
            return message.snippet
        }
    }

    public func fetchHTMLBody(for message: MailMessage) async throws -> String? {
        try await withMessage(message) { client, uid in
            guard let structure = try await client.uidFetch(uid: uid, items: "BODYSTRUCTURE"),
                  let html = Self.textParts(structure.parts).html else { return nil }
            return try await Self.fetchPart(html, uid: uid, client: client)
        }
    }

    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        try await withMessage(message) { client, uid in
            guard let structure = try await client.uidFetch(uid: uid, items: "BODYSTRUCTURE"),
                  let part = structure.parts.first(where: { $0.number == attachment.id }),
                  let fetched = try await client.uidFetch(uid: uid, items: "BODY.PEEK[\(part.number)]"),
                  let raw = fetched.section(prefix: "BODY[\(part.number)]") else {
                throw MailProviderError.network("Could not download the attachment.")
            }
            return MIMEText.decodeTransfer(raw, encoding: part.encoding)
        }
    }

    // MARK: Sessions

    /// "inbox:123" / "sent:45": which mailbox and which UID a message lives at.
    static func messageID(_ mailbox: Mailbox, uid: Int) -> String { "\(mailbox.rawValue):\(uid)" }

    static func parseMessageID(_ id: String) -> (Mailbox, Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, let box = Mailbox(rawValue: String(parts[0])), let uid = Int(parts[1]) else { return nil }
        return (box, uid)
    }

    private func session<T: Sendable>(_ body: @Sendable (IMAPClient) async throws -> T) async throws -> T {
        guard let json = try secrets.get(Self.keychainKey(for: account.id)),
              let creds = try? JSONDecoder().decode(IMAPCredentials.self, from: Data(json.utf8)) else {
            throw MailProviderError.notAuthorized
        }
        return try await Self.withSession(credentials: creds, transportFactory: transportFactory, body)
    }

    private func withMessage<T: Sendable>(_ message: MailMessage,
                                          _ body: @Sendable @escaping (IMAPClient, Int) async throws -> T) async throws -> T {
        guard let (box, uid) = Self.parseMessageID(message.providerMessageID) else {
            throw MailProviderError.network("Unrecognised message id.")
        }
        return try await session { client in
            guard let name = try await resolve(box, using: client) else { throw MailProviderError.network("Mailbox not found.") }
            _ = try await client.examine(name)
            return try await body(client, uid)
        }
    }

    /// Connects, signs in, runs `body`, signs out. A watchdog closes the connection if the
    /// server stops answering, so nothing can hang forever.
    private static func withSession<T: Sendable>(credentials: IMAPCredentials,
                                                 transportFactory: @Sendable () -> any IMAPTransport,
                                                 _ body: @Sendable (IMAPClient) async throws -> T) async throws -> T {
        let transport = transportFactory()
        let client = IMAPClient(transport: transport)
        let watchdog = Task {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            await transport.close()
        }
        defer { watchdog.cancel() }
        do {
            try await client.connect(host: credentials.host, port: credentials.port)
            do {
                try await client.login(user: credentials.username, password: credentials.password)
            } catch IMAPError.loginFailed where credentials.host.hasSuffix("mail.me.com") && credentials.username.contains("@") {
                // Some iCloud accounts sign in with just the part before the @.
                try await client.login(user: String(credentials.username.split(separator: "@")[0]),
                                       password: credentials.password)
            }
            let result = try await body(client)
            await client.logout()
            return result
        } catch let error as IMAPError {
            await client.close()
            switch error {
            case .loginFailed:
                throw MailProviderError.network("The mail server rejected the sign-in. Check the email address and app-specific password.")
            default:
                throw MailProviderError.network(error.localizedDescription)
            }
        } catch {
            await client.close()
            throw error
        }
    }

    /// Finds the real mailbox name: INBOX, or the server's Sent folder.
    private func resolve(_ mailbox: Mailbox, using client: IMAPClient) async throws -> String? {
        if mailbox == .inbox { return "INBOX" }
        let all = try await client.listMailboxes()
        if let sent = all.first(where: \.isSent) { return sent.name }
        let names = ["Sent Messages", "Sent", "Sent Items", "INBOX.Sent"]
        return all.first { names.contains($0.name) }?.name
    }

    // MARK: Conversion

    static let listItems = "UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE BODY.PEEK[HEADER.FIELDS (LIST-UNSUBSCRIBE LIST-ID PRECEDENCE)]"

    static func textParts(_ parts: [IMAPBodyPart]) -> (plain: IMAPBodyPart?, html: IMAPBodyPart?) {
        (parts.first { $0.type == "text" && $0.subtype == "plain" && !$0.isAttachment },
         parts.first { $0.type == "text" && $0.subtype == "html" && !$0.isAttachment })
    }

    private static func fetchPart(_ part: IMAPBodyPart, uid: Int, client: IMAPClient) async throws -> String? {
        guard let fetched = try await client.uidFetch(uid: uid, items: "BODY.PEEK[\(part.number)]<0.300000>"),
              let raw = fetched.section(prefix: "BODY[\(part.number)]") else { return nil }
        let decoded = MIMEText.decodeTransfer(raw, encoding: part.encoding)
        return MIMEText.string(from: decoded, charset: part.charset)
    }

    static func snippet(from raw: Data, part: IMAPBodyPart) -> String {
        let decoded = MIMEText.decodeTransfer(raw, encoding: part.encoding)
        var text = MIMEText.string(from: decoded, charset: part.charset)
        if part.subtype == "html" { text = HTMLText.strip(text) }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(200))
    }

    static func convert(_ item: IMAPFetch, uid: Int, mailbox: Mailbox, snippet: String, accountID: UUID) -> MailMessage {
        let env = item.envelope
        let header = item.sections.first { $0.key.hasPrefix("BODY[HEADER") }
            .map { String(decoding: $0.value, as: UTF8.self).lowercased() } ?? ""
        let from = env?.from.first ?? MailAddress(address: "unknown")
        let bulk = BulkMailDetector.isBulk(fromAddress: from.address,
                                           hasListUnsubscribe: header.contains("list-unsubscribe:"),
                                           hasListID: header.contains("list-id:"),
                                           precedence: ["bulk", "list", "junk"].first { header.contains("precedence: \($0)") })
        let attachments = item.parts.filter(\.isAttachment).map { part in
            AttachmentInfo(id: part.number, filename: part.filename ?? "attachment", mimeType: "\(part.type)/\(part.subtype)",
                           byteCount: part.size, kind: GmailProvider.kind(mime: "\(part.type)/\(part.subtype)",
                                                                          filename: part.filename ?? ""))
        }
        let subject = (env?.subject?.isEmpty == false ? env?.subject : nil) ?? "(no subject)"
        return MailMessage(
            accountID: accountID,
            providerMessageID: messageID(mailbox, uid: uid),
            threadID: "s:" + MIMEText.normalizedSubject(subject),
            from: from,
            to: env?.to ?? [],
            subject: subject,
            snippet: snippet,
            receivedAt: item.internalDate ?? Date(),
            isRead: item.isRead,
            attachments: attachments,
            isBulk: bulk
        )
    }
}
