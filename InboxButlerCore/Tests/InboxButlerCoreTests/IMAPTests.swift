import XCTest
@testable import InboxButlerCore

/// A fake mail server: replies to each command from a script, in tiny chunks.
private final class ScriptedTransport: IMAPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data] = []
    private(set) var commands: [String] = []
    private let handler: @Sendable (String, String) -> [String]   // (tag, command) -> raw reply pieces

    init(handler: @escaping @Sendable (String, String) -> [String]) {
        self.handler = handler
        queue = [Data("* OK IMAP ready\r\n".utf8)]
    }

    func connect(host: String, port: Int) async throws {}

    func send(_ data: Data) async throws {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = String(text.split(separator: " ")[0])
        let command = String(text.dropFirst(tag.count + 1))
        lock.lock(); defer { lock.unlock() }
        commands.append(command)
        for reply in handler(tag, command) {
            let bytes = Array(reply.utf8)
            var i = 0
            while i < bytes.count {                       // deliver in 7-byte pieces
                queue.append(Data(bytes[i..<min(i + 7, bytes.count)]))
                i += 7
            }
        }
    }

    func receive() async throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if queue.isEmpty { throw IMAPError.connectionClosed }
        return queue.removeFirst()
    }

    func close() async {}
}

final class IMAPTests: XCTestCase {
    // MARK: Canned server data

    private static let header1 = "List-Unsubscribe: <mailto:u@x.com>\r\n\r\n"
    private static let envelope1 = #"("Fri, 6 Nov 2026 10:00:00 +1000" "=?utf-8?B?Q2Fmw6k=?=" (("Sam Rivera" NIL "sam" "work.com")) (("Sam Rivera" NIL "sam" "work.com")) (("Sam Rivera" NIL "sam" "work.com")) ((NIL NIL "me" "icloud.com")) NIL NIL NIL "<id1@work.com>")"#
    private static let structure1 = #"(("text" "plain" ("charset" "utf-8") NIL NIL "quoted-printable" 42 3 NIL NIL NIL)("application" "pdf" ("name" "Invoice.pdf") NIL NIL "base64" 2048 NIL ("attachment" ("filename" "Invoice.pdf")) NIL) "mixed" ("boundary" "xyz") NIL NIL)"#
    private static let envelope2 = #"("Sat, 7 Nov 2026 09:00:00 +1000" "Lunch?" (("Mum" NIL "mum" "home.net")) (("Mum" NIL "mum" "home.net")) (("Mum" NIL "mum" "home.net")) ((NIL NIL "me" "icloud.com")) NIL NIL NIL "<id2@home.net>")"#
    private static let structure2 = #"("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 20 1 NIL NIL NIL)"#
    private static let qpBody = "Caf=C3=A9 au lait=\r\n est pr=C3=AAt"

    private static func fetch1() -> String {
        "* 1 FETCH (UID 101 FLAGS (\\Seen) INTERNALDATE \"06-Nov-2026 10:00:00 +1000\" ENVELOPE \(envelope1) BODYSTRUCTURE \(structure1) BODY[HEADER.FIELDS (LIST-UNSUBSCRIBE LIST-ID PRECEDENCE)] {\(header1.utf8.count)}\r\n\(header1))\r\n"
    }
    private static func fetch2() -> String {
        "* 2 FETCH (UID 102 FLAGS () INTERNALDATE \"07-Nov-2026 09:00:00 +1000\" ENVELOPE \(envelope2) BODYSTRUCTURE \(structure2) BODY[HEADER.FIELDS (LIST-UNSUBSCRIBE LIST-ID PRECEDENCE)] {2}\r\n\r\n)\r\n"
    }
    private static func literal(_ section: String, _ body: String, uid: Int, seq: Int) -> String {
        "* \(seq) FETCH (UID \(uid) \(section) {\(body.utf8.count)}\r\n\(body))\r\n"
    }

    /// The scripted server used by most tests.
    private static func server(_ tag: String, _ command: String) -> [String] {
        let ok = "\(tag) OK done\r\n"
        switch true {
        case command.hasPrefix("LOGIN"): return [ok]
        case command.hasPrefix("LIST"):
            return ["* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n", "* LIST (\\HasNoChildren \\Sent) \"/\" \"Sent Messages\"\r\n", ok]
        case command.hasPrefix("EXAMINE"): return ["* 2 EXISTS\r\n", ok]
        case command.hasPrefix("FETCH 1:2"): return [fetch1(), fetch2(), ok]
        case command == "UID FETCH 101 (BODY.PEEK[1]<0.600>)":
            return [literal("BODY[1]<0>", qpBody, uid: 101, seq: 1), ok]
        case command == "UID FETCH 102 (BODY.PEEK[1]<0.600>)":
            return [literal("BODY[1]<0>", "Hello Mum", uid: 102, seq: 2), ok]
        case command == "UID FETCH 101 (BODYSTRUCTURE)":
            return ["* 1 FETCH (UID 101 BODYSTRUCTURE \(structure1))\r\n", ok]
        case command == "UID FETCH 101 (BODY.PEEK[1]<0.300000>)":
            return [literal("BODY[1]<0>", qpBody, uid: 101, seq: 1), ok]
        case command == "UID FETCH 101 (BODY.PEEK[2])":
            return [literal("BODY[2]", "UERGREFUQQ==", uid: 101, seq: 1), ok]      // base64 of "PDFDATA"
        case command.hasPrefix("LOGOUT"): return ["* BYE\r\n", ok]
        default: return ["\(tag) BAD unknown\r\n"]
        }
    }

    private func makeProvider(_ transport: ScriptedTransport) throws -> (IMAPProvider, MailAccount) {
        let account = MailAccount(kind: .icloud, emailAddress: "me@icloud.com", label: "iCloud", colorIndex: 2)
        let secrets = InMemorySecretStore()
        try IMAPProvider.save(.icloud(email: "me@icloud.com", appPassword: "abcd-efgh-ijkl-mnop"), for: account.id, in: secrets)
        return (IMAPProvider(account: account, secrets: secrets, transportFactory: { transport }), account)
    }

    // MARK: Provider tests

    func testFetchMessagesParsesInboxFromScriptedServer() async throws {
        let transport = ScriptedTransport(handler: Self.server)
        let (provider, account) = try makeProvider(transport)
        let page = try await provider.fetchMessages(in: .inbox, since: nil, limit: 50)

        XCTAssertEqual(page.messages.count, 2)
        let (mum, sam) = (page.messages[0], page.messages[1])    // newest first

        XCTAssertEqual(mum.subject, "Lunch?")
        XCTAssertEqual(mum.from.address, "mum@home.net")
        XCTAssertEqual(mum.from.name, "Mum")
        XCTAssertFalse(mum.isRead)
        XCTAssertEqual(mum.snippet, "Hello Mum")
        XCTAssertFalse(mum.isBulk)
        XCTAssertEqual(mum.providerMessageID, "inbox:102")

        XCTAssertEqual(sam.subject, "Café")                       // RFC 2047 decoded
        XCTAssertEqual(sam.from.name, "Sam Rivera")
        XCTAssertEqual(sam.from.address, "sam@work.com")
        XCTAssertEqual(sam.to.first?.address, "me@icloud.com")
        XCTAssertTrue(sam.isRead)
        XCTAssertTrue(sam.isBulk)                                 // List-Unsubscribe header
        XCTAssertEqual(sam.snippet, "Café au lait est prêt")      // quoted-printable decoded
        XCTAssertEqual(sam.threadID, "s:café")
        XCTAssertEqual(sam.accountID, account.id)
        XCTAssertEqual(sam.receivedAt, ISO8601DateFormatter().date(from: "2026-11-06T00:00:00Z"))
        XCTAssertEqual(sam.attachments.count, 1)
        XCTAssertEqual(sam.attachments[0].filename, "Invoice.pdf")
        XCTAssertEqual(sam.attachments[0].kind, .pdf)
        XCTAssertEqual(sam.attachments[0].id, "2")
        XCTAssertEqual(sam.attachments[0].byteCount, 2048)
    }

    func testClientIsReadOnly() async throws {
        let transport = ScriptedTransport(handler: Self.server)
        let (provider, _) = try makeProvider(transport)
        _ = try await provider.fetchMessages(in: .inbox, since: nil, limit: 50)
        let verbs = Set(transport.commands.map { String($0.split(separator: " ")[0]) })
        // Only these verbs are ever sent: no STORE, COPY, MOVE, EXPUNGE, APPEND, DELETE...
        XCTAssertTrue(verbs.isSubset(of: ["LOGIN", "EXAMINE", "FETCH", "UID", "LIST", "LOGOUT"]), "\(verbs)")
        XCTAssertFalse(transport.commands.contains { $0.hasPrefix("SELECT") })
        XCTAssertFalse(transport.commands.contains { $0.contains("BODY[") && !$0.contains("PEEK") && !$0.contains("HEADER") })
    }

    func testFetchBodyDecodesQuotedPrintable() async throws {
        let transport = ScriptedTransport(handler: Self.server)
        let (provider, account) = try makeProvider(transport)
        let message = MailMessage(accountID: account.id, providerMessageID: "inbox:101", from: MailAddress(address: "a@b.c"),
                                  subject: "", snippet: "fallback", receivedAt: Date())
        let body = try await provider.fetchBody(for: message)
        XCTAssertEqual(body, "Café au lait est prêt")
    }

    func testFetchAttachmentDecodesBase64() async throws {
        let transport = ScriptedTransport(handler: Self.server)
        let (provider, account) = try makeProvider(transport)
        let message = MailMessage(accountID: account.id, providerMessageID: "inbox:101", from: MailAddress(address: "a@b.c"),
                                  subject: "", snippet: "", receivedAt: Date())
        let attachment = AttachmentInfo(id: "2", filename: "Invoice.pdf", mimeType: "application/pdf", byteCount: 2048, kind: .pdf)
        let data = try await provider.fetchAttachment(attachment, in: message)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "PDFDATA")
    }

    func testSentMailboxIsFoundBySpecialUseFlag() async throws {
        let transport = ScriptedTransport(handler: Self.server)
        let (provider, _) = try makeProvider(transport)
        _ = try await provider.fetchMessages(in: .sent, since: nil, limit: 10)
        XCTAssertTrue(transport.commands.contains("EXAMINE \"Sent Messages\""), "\(transport.commands)")
    }

    func testWrongPasswordGivesAFriendlyError() async {
        let transport = ScriptedTransport { tag, command in
            command.hasPrefix("LOGIN") ? ["\(tag) NO [AUTHENTICATIONFAILED] Invalid credentials\r\n"] : ["\(tag) OK\r\n"]
        }
        do {
            try await IMAPProvider.verify(.icloud(email: "me@icloud.com", appPassword: "wrong"),
                                          transportFactory: { transport })
            XCTFail("Expected a failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("rejected"), error.localizedDescription)
        }
    }

    func testNotSignedInWhenNoCredentialsAreStored() async {
        let account = MailAccount(kind: .icloud, emailAddress: "me@icloud.com", label: "iCloud", colorIndex: 0)
        let provider = IMAPProvider(account: account, secrets: InMemorySecretStore(), transportFactory: { ScriptedTransport(handler: Self.server) })
        do { _ = try await provider.fetchMessages(in: .inbox, since: nil, limit: 10); XCTFail("Expected failure") }
        catch { XCTAssertEqual((error as? MailProviderError)?.errorDescription, MailProviderError.notAuthorized.errorDescription) }
    }

    // MARK: Parser and decoder unit tests

    func testParserHandlesLiteralsQuotedStringsAndNil() throws {
        var parser = IMAPParser(Data("(\"a \\\"b\\\"\" NIL {5}\r\nhello 12 BODY[HEADER.FIELDS (X Y)])".utf8))
        let value = try parser.parseValue()
        guard case .list(let items) = value else { return XCTFail("not a list") }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0].text, "a \"b\"")
        XCTAssertTrue(items[1].isNull)
        XCTAssertEqual(items[2].text, "hello")
        XCTAssertEqual(items[3].intValue, 12)
        XCTAssertEqual(items[4].text, "BODY[HEADER.FIELDS (X Y)]")
    }

    func testEncodedWordsAndTransferEncodings() {
        XCTAssertEqual(MIMEText.decodeEncodedWords("=?ISO-8859-1?Q?Andr=E9_Dupont?= <a@b.c>"), "André Dupont <a@b.c>")
        XCTAssertEqual(MIMEText.decodeEncodedWords("=?utf-8?B?SGVsbG8g?= =?utf-8?B?V29ybGQ=?="), "Hello World")
        XCTAssertEqual(MIMEText.decodeEncodedWords("plain text"), "plain text")
        XCTAssertEqual(String(decoding: MIMEText.decodeQuotedPrintable(Data("a=3Db=\r\nc".utf8)), as: UTF8.self), "a=bc")
        XCTAssertEqual(String(decoding: MIMEText.decodeTransfer(Data("SGVsbG8=\r\n".utf8), encoding: "base64"), as: UTF8.self), "Hello")
        XCTAssertEqual(MIMEText.normalizedSubject("RE: Fwd:  Re: Hello   World"), "hello world")
    }

    func testRFC2231FilenameAndAttachmentRules() {
        XCTAssertEqual(MIMEText.parameter(["filename*": "utf-8''Caf%C3%A9.pdf"], "filename"), "Café.pdf")
        let inlineImage = IMAPBodyPart(number: "2", type: "image", subtype: "png", params: ["name": "logo.png"], disposition: "inline",
                                       dispositionParams: [:], size: 1, encoding: "base64")
        let body = IMAPBodyPart(number: "1", type: "text", subtype: "plain", params: [:], disposition: nil,
                                dispositionParams: [:], size: 1, encoding: "7bit")
        let pdf = IMAPBodyPart(number: "3", type: "application", subtype: "pdf", params: ["name": "a.pdf"], disposition: nil,
                               dispositionParams: [:], size: 1, encoding: "base64")
        XCTAssertFalse(inlineImage.isAttachment)
        XCTAssertFalse(body.isAttachment)
        XCTAssertTrue(pdf.isAttachment)
    }
}
