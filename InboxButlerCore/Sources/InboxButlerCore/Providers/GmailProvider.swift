import Foundation

/// Gmail via the REST API with the READ-ONLY scope (`gmail.readonly`).
/// There is no code in this type that sends, deletes, archives or labels mail.
///
/// Interactive sign-in (the web sheet) lives in the app target because it needs
/// UI; it stores tokens through `GoogleTokenManager`. `authorize()` here only
/// checks that a working sign-in already exists.
public struct GmailProvider: MailProvider {
    public let account: MailAccount
    private let tokens: GoogleTokenManager
    private let transport: HTTPTransport
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    public init(account: MailAccount, tokens: GoogleTokenManager,
                transport: HTTPTransport = URLSessionTransport()) {
        self.account = account
        self.tokens = tokens
        self.transport = transport
    }

    public func authorize() async throws {
        _ = try await tokens.accessToken()
    }

    /// The signed-in address, used to name the account after sign-in.
    public func fetchEmailAddress() async throws -> String {
        let (data, status) = try await get("profile")
        guard status == 200, let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
            throw MailProviderError.network("Could not read the Gmail profile (\(status)).")
        }
        return profile.emailAddress
    }

    // MARK: MailProvider

    /// Returns the latest `limit` messages. (Incremental sync via historyId arrives
    /// with the local cache; for now each refresh re-reads the newest page.)
    public func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        let label = mailbox == .inbox ? "INBOX" : "SENT"
        let (listData, status) = try await get("messages", query: [
            .init(name: "labelIds", value: label),
            .init(name: "maxResults", value: String(min(max(limit, 1), 100))),
            .init(name: "fields", value: "messages/id")
        ])
        guard status == 200 else { throw MailProviderError.network("Gmail returned \(status) listing mail.") }
        let ids = (try? JSONDecoder().decode(ListResponse.self, from: listData))?.messages?.map(\.id) ?? []
        let labelMap = await fetchLabelMap()

        // Fetch details 10 at a time to stay well inside Gmail's rate limits.
        var result: [MailMessage] = []
        for chunk in stride(from: 0, to: ids.count, by: 10).map({ Array(ids[$0..<min($0 + 10, ids.count)]) }) {
            let fetched = try await withThrowingTaskGroup(of: MailMessage?.self) { group in
                for id in chunk { group.addTask { try await self.fetchOne(id, labelMap: labelMap) } }
                var out: [MailMessage] = []
                for try await message in group { if let message { out.append(message) } }
                return out
            }
            result.append(contentsOf: fetched)
        }
        result.sort { $0.receivedAt > $1.receivedAt }
        return MailPage(messages: result, nextCursor: nil)
    }

    public func fetchBody(for message: MailMessage) async throws -> String {
        let (data, status) = try await get("messages/\(message.providerMessageID)", query: [
            .init(name: "format", value: "full"),
            .init(name: "fields", value: Self.bodyFields)
        ])
        guard status == 200, let raw = try? JSONDecoder().decode(RawMessage.self, from: data) else {
            throw MailProviderError.network("Gmail returned \(status) reading the message.")
        }
        if let plain = Self.firstBody(in: raw.payload, mime: "text/plain") { return plain }
        if let html = Self.firstBody(in: raw.payload, mime: "text/html") { return HTMLText.strip(html) }
        // Large text parts come back as attachments, not inline data.
        for mime in ["text/plain", "text/html"] {
            guard let id = Self.textAttachmentID(in: raw.payload, mime: mime) else { continue }
            let (d, s) = try await get("messages/\(message.providerMessageID)/attachments/\(id)")
            if s == 200, let part = try? JSONDecoder().decode(AttachmentBody.self, from: d),
               let bytes = Self.decodeBase64URL(part.data) {
                let text = String(decoding: bytes, as: UTF8.self)
                return mime == "text/html" ? HTMLText.strip(text) : text
            }
        }
        return message.snippet
    }

    public func fetchHTMLBody(for message: MailMessage) async throws -> String? {
        let (data, status) = try await get("messages/\(message.providerMessageID)", query: [
            .init(name: "format", value: "full"),
            .init(name: "fields", value: Self.bodyFields)
        ])
        guard status == 200, let raw = try? JSONDecoder().decode(RawMessage.self, from: data) else {
            throw MailProviderError.network("Gmail returned \(status) reading the message.")
        }
        return Self.firstBody(in: raw.payload, mime: "text/html")
    }

    public func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data {
        let (data, status) = try await get("messages/\(message.providerMessageID)/attachments/\(attachment.id)")
        guard status == 200, let body = try? JSONDecoder().decode(AttachmentBody.self, from: data),
              let bytes = Self.decodeBase64URL(body.data) else {
            throw MailProviderError.network("Could not download the attachment (\(status)).")
        }
        return bytes
    }

    // MARK: Fetching

    /// Only the fields we need; `fields` keeps responses small (no message bodies).
    private static let messageFields =
        "id,threadId,labelIds,snippet,internalDate," +
        "payload(headers,parts(filename,mimeType,body(attachmentId,size)," +
        "parts(filename,mimeType,body(attachmentId,size))))"

    /// Body text only (up to 4 levels of nesting), no headers or attachment metadata.
    /// Whole MIME tree (any depth), so deeply nested messages from Outlook and school systems
    /// still yield their text. Attachment bytes are never inline, so this stays small.
    private static let bodyFields = "payload(mimeType,body(data,attachmentId),parts)"

    /// Id of a text part whose content is too big to be inline (Gmail serves it as an attachment).
    static func textAttachmentID(in part: RawMessage.Part?, mime: String) -> String? {
        guard let part else { return nil }
        if part.mimeType?.lowercased() == mime, part.body?.data == nil, let id = part.body?.attachmentId { return id }
        for child in part.parts ?? [] { if let found = textAttachmentID(in: child, mime: mime) { return found } }
        return nil
    }

    /// First part of the given MIME type that has inline data, decoded as UTF-8.
    static func firstBody(in part: RawMessage.Part?, mime: String) -> String? {
        guard let part else { return nil }
        if part.mimeType?.lowercased() == mime, let encoded = part.body?.data,
           let bytes = decodeBase64URL(encoded) {
            return String(decoding: bytes, as: UTF8.self)
        }
        for child in part.parts ?? [] { if let found = firstBody(in: child, mime: mime) { return found } }
        return nil
    }

    /// The user's own labels (name and colour), so the inbox can show them. Read-only; if it fails,
    /// mail simply shows without label chips.
    func fetchLabelMap() async -> [String: MailLabelTag] {
        guard let (data, status) = try? await get("labels", query: [.init(name: "fields", value: "labels(id,name,type,color)")]),
              status == 200, let list = try? JSONDecoder().decode(LabelList.self, from: data) else { return [:] }
        var map: [String: MailLabelTag] = [:]
        for label in list.labels ?? [] where label.type == "user" {
            map[label.id] = MailLabelTag(name: label.name, colorHex: label.color?.backgroundColor.flatMap(Self.parseHexColor))
        }
        return map
    }

    static func parseHexColor(_ s: String) -> UInt32? {
        UInt32(s.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
    }

    private struct LabelList: Decodable {
        struct Label: Decodable {
            struct Color: Decodable { let backgroundColor: String? }
            let id: String; let name: String; let type: String?; let color: Color?
        }
        let labels: [Label]?
    }

    private func fetchOne(_ id: String, labelMap: [String: MailLabelTag] = [:]) async throws -> MailMessage? {
        let (data, status) = try await get("messages/\(id)", query: [
            .init(name: "format", value: "full"),
            .init(name: "fields", value: Self.messageFields)
        ])
        if status == 404 { return nil }   // deleted between list and fetch
        guard status == 200, let raw = try? JSONDecoder().decode(RawMessage.self, from: data) else {
            throw MailProviderError.network("Gmail returned \(status) reading a message.")
        }
        return Self.convert(raw, accountID: account.id, labelMap: labelMap)
    }

    /// GET with a bearer token. On 401 refreshes the token once and retries.
    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> (Data, Int) {
        var token = try await tokens.accessToken()
        for attempt in 0..<2 {
            var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = query.isEmpty ? nil : query
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, http) = try await transport.send(request)
            if http.statusCode == 401 {
                if attempt == 0 { token = try await tokens.accessToken(forceRefresh: true); continue }
                throw MailProviderError.notAuthorized
            }
            if http.statusCode == 429 {
                throw MailProviderError.network("Gmail is rate limiting requests. Try again shortly.")
            }
            return (data, http.statusCode)
        }
        throw MailProviderError.notAuthorized
    }

    // MARK: Wire formats and conversion

    private struct Profile: Decodable { let emailAddress: String }
    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
    }
    private struct AttachmentBody: Decodable { let data: String }

    struct RawMessage: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let attachmentId: String?; let size: Int?; let data: String? }
        struct Part: Decodable {
            let headers: [Header]?
            let filename: String?
            let mimeType: String?
            let body: Body?
            let parts: [Part]?
        }
        let id: String
        let threadId: String?
        let labelIds: [String]?
        let snippet: String?
        let internalDate: String?
        let payload: Part?
    }

    static func convert(_ raw: RawMessage, accountID: UUID, labelMap: [String: MailLabelTag] = [:]) -> MailMessage {
        func header(_ name: String) -> String? {
            raw.payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let millis = Double(raw.internalDate ?? "") ?? 0
        let from = header("From").map { parseAddresses($0).first ?? MailAddress(address: $0) } ?? MailAddress(address: "unknown")
        let bulk = BulkMailDetector.isBulk(fromAddress: from.address,
                                           hasListUnsubscribe: header("List-Unsubscribe") != nil,
                                           hasListID: header("List-Id") != nil,
                                           precedence: header("Precedence"))
        return MailMessage(
            accountID: accountID,
            providerMessageID: raw.id,
            threadID: raw.threadId,
            from: from,
            to: header("To").map(parseAddresses) ?? [],
            subject: header("Subject").flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)",
            snippet: decodeEntities(raw.snippet ?? ""),
            receivedAt: Date(timeIntervalSince1970: millis / 1000),
            isRead: !(raw.labelIds ?? []).contains("UNREAD"),
            attachments: attachments(in: raw.payload),
            isBulk: bulk,
            labels: (raw.labelIds ?? []).compactMap { labelMap[$0] }.sorted { $0.name < $1.name }
        )
    }

    private static func attachments(in part: RawMessage.Part?) -> [AttachmentInfo] {
        guard let part else { return [] }
        var found: [AttachmentInfo] = []
        if let name = part.filename, !name.isEmpty, let id = part.body?.attachmentId {
            let mime = part.mimeType ?? "application/octet-stream"
            found.append(AttachmentInfo(id: id, filename: name, mimeType: mime,
                                        byteCount: part.body?.size ?? 0, kind: kind(mime: mime, filename: name)))
        }
        for child in part.parts ?? [] { found.append(contentsOf: attachments(in: child)) }
        return found
    }

    static func kind(mime: String, filename: String) -> AttachmentInfo.Kind {
        let m = mime.lowercased(), f = filename.lowercased()
        if m == "application/pdf" || f.hasSuffix(".pdf") { return .pdf }
        if m.hasPrefix("image/") { return .image }
        if m == "text/calendar" || f.hasSuffix(".ics") { return .calendar }
        if m.contains("wordprocessingml") || m == "application/msword" || f.hasSuffix(".docx") || f.hasSuffix(".doc") {
            return .wordDocument
        }
        return .other
    }

    /// Parses `Name <a@b.com>, "Last, First" <c@d.com>, e@f.com`.
    static func parseAddresses(_ raw: String) -> [MailAddress] {
        var pieces: [String] = []
        var current = ""
        var inQuotes = false
        for ch in raw {
            if ch == "\"" { inQuotes.toggle() }
            if ch == "," && !inQuotes { pieces.append(current); current = "" } else { current.append(ch) }
        }
        pieces.append(current)
        return pieces.compactMap { piece in
            let p = piece.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            if let open = p.lastIndex(of: "<"), let close = p.lastIndex(of: ">"), open < close {
                let address = String(p[p.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
                let name = p[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
                return MailAddress(name: name.isEmpty ? nil : name, address: address)
            }
            return MailAddress(address: p)
        }
    }

    /// Gmail snippets arrive HTML-escaped (e.g. `&#39;`).
    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func decodeBase64URL(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}
