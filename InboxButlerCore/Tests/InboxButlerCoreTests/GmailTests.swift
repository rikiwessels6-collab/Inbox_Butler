import XCTest
@testable import InboxButlerCore

/// Canned-response network for tests.
private struct FakeTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) -> (Int, String)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

final class GmailTests: XCTestCase {
    func testPKCEMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testRedirectSchemeIsReversedClientID() {
        let c = GoogleOAuthConfig(clientID: "123-abc.apps.googleusercontent.com")
        XCTAssertTrue(c.isConfigured)
        XCTAssertEqual(c.callbackScheme, "com.googleusercontent.apps.123-abc")
        XCTAssertFalse(GoogleOAuthConfig.default.isConfigured)
    }

    func testAuthorizationURLRequestsReadOnlyScopeAndPKCE() {
        let url = GoogleAuth(config: GoogleOAuthConfig(clientID: "1.apps.googleusercontent.com"))
            .authorizationURL(pkce: PKCE(verifier: "v"), state: "s").absoluteString
        XCTAssertTrue(url.contains("gmail.readonly"))
        XCTAssertFalse(url.contains("gmail.modify") || url.contains("gmail.send"))
        XCTAssertTrue(url.contains("code_challenge_method=S256"))
    }

    func testAddressParsing() {
        let list = GmailProvider.parseAddresses("\"Rivera, Sam\" <sam@work.com>, plain@x.org, Mum <mum@home.net>")
        XCTAssertEqual(list.map(\.address), ["sam@work.com", "plain@x.org", "mum@home.net"])
        XCTAssertEqual(list.first?.name, "Rivera, Sam")
        XCTAssertNil(list[1].name)
    }

    func testFetchMessagesParsesGmailJSON() async throws {
        let account = MailAccount(kind: .gmail, emailAddress: "me@gmail.com", label: "Personal", colorIndex: 0)
        let secrets = InMemorySecretStore()
        let manager = GoogleTokenManager(accountID: account.id, auth: GoogleAuth(), secrets: secrets)
        try await manager.save(GoogleTokens(accessToken: "tok", refreshToken: "ref",
                                            expiresAt: Date().addingTimeInterval(3600)))

        let message = """
        {"id":"m1","threadId":"t1","labelIds":["INBOX","UNREAD"],"snippet":"Don&#39;t forget &amp; sign",
         "internalDate":"1700000000000",
         "payload":{"headers":[{"name":"From","value":"Sam Rivera <sam@work.com>"},
                               {"name":"to","value":"me@gmail.com"},
                               {"name":"Subject","value":"Contract"}],
                    "parts":[{"filename":"","mimeType":"text/plain","body":{}},
                             {"filename":"c.pdf","mimeType":"application/pdf","body":{"attachmentId":"att1","size":1234}}]}}
        """
        let transport = FakeTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            let path = request.url!.path
            if path.hasSuffix("/messages") { return (200, #"{"messages":[{"id":"m1"}]}"#) }
            if path.hasSuffix("/messages/m1") { return (200, message) }
            return (404, "{}")
        }
        let provider = GmailProvider(account: account, tokens: manager, transport: transport)
        let page = try await provider.fetchMessages(in: .inbox, since: nil, limit: 10)

        XCTAssertEqual(page.messages.count, 1)
        let m = page.messages[0]
        XCTAssertEqual(m.subject, "Contract")
        XCTAssertEqual(m.from.address, "sam@work.com")
        XCTAssertEqual(m.from.name, "Sam Rivera")
        XCTAssertFalse(m.isRead)
        XCTAssertEqual(m.snippet, "Don't forget & sign")
        XCTAssertEqual(m.receivedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(m.attachments.count, 1)
        XCTAssertEqual(m.attachments[0].kind, .pdf)
        XCTAssertEqual(m.attachments[0].id, "att1")
    }

    func testAttachmentDownloadDecodesBase64URL() async throws {
        let account = MailAccount(kind: .gmail, emailAddress: "me@gmail.com", label: "P", colorIndex: 0)
        let manager = GoogleTokenManager(accountID: account.id, auth: GoogleAuth(), secrets: InMemorySecretStore())
        try await manager.save(GoogleTokens(accessToken: "tok", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600)))
        let transport = FakeTransport { _ in (200, #"{"data":"aGVsbG8_"}"#) }   // "hello?" in base64url
        let provider = GmailProvider(account: account, tokens: manager, transport: transport)
        let msg = MailMessage(accountID: account.id, providerMessageID: "m1", from: MailAddress(address: "a@b.c"),
                              subject: "", snippet: "", receivedAt: Date())
        let data = try await provider.fetchAttachment(
            AttachmentInfo(id: "att1", filename: "a.txt", mimeType: "text/plain", byteCount: 6, kind: .other), in: msg)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello?")
    }
}
