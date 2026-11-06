import Foundation

/// Google OAuth settings. The client ID is NOT a secret (iOS "public" clients have
/// no client secret). Replace the placeholder with the ID from Google Cloud Console
/// (see docs/SETUP_GOOGLE.md).
public struct GoogleOAuthConfig: Sendable {
    public var clientID: String

    /// Read-only Gmail access. Nothing here can send, delete or change mail.
    public static let scopes = ["https://www.googleapis.com/auth/gmail.readonly"]

    public static let `default` = GoogleOAuthConfig(clientID: "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com")

    public init(clientID: String) { self.clientID = clientID }

    private static let suffix = ".apps.googleusercontent.com"

    public var isConfigured: Bool { !clientID.hasPrefix("YOUR_") && clientID.hasSuffix(Self.suffix) }

    /// Google's iOS clients use the reversed client ID as the redirect URL scheme.
    public var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: Self.suffix, with: "")
    }
    public var redirectURI: String { callbackScheme + ":/oauth2redirect" }
}

public struct GoogleTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
}

/// The three OAuth calls: build the sign-in URL, swap the code for tokens, refresh.
public struct GoogleAuth: Sendable {
    public let config: GoogleOAuthConfig
    private let transport: HTTPTransport
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!

    public init(config: GoogleOAuthConfig = .default, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    /// URL to open in the system web sign-in sheet.
    public func authorizationURL(pkce: PKCE, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),   // we need a refresh token
            .init(name: "prompt", value: "consent")          // always return one
        ]
        return c.url!
    }

    public func exchange(code: String, pkce: PKCE) async throws -> GoogleTokens {
        let response = try await tokenRequest([
            ("client_id", config.clientID), ("code", code), ("code_verifier", pkce.verifier),
            ("grant_type", "authorization_code"), ("redirect_uri", config.redirectURI)
        ])
        guard let refresh = response.refresh_token else {
            throw MailProviderError.network("Google did not return a refresh token. Remove the app at myaccount.google.com/permissions and sign in again.")
        }
        return GoogleTokens(accessToken: response.access_token, refreshToken: refresh,
                            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)))
    }

    public func refresh(_ tokens: GoogleTokens) async throws -> GoogleTokens {
        let response = try await tokenRequest([
            ("client_id", config.clientID), ("refresh_token", tokens.refreshToken), ("grant_type", "refresh_token")
        ])
        // Google normally omits refresh_token on refresh: keep the existing one.
        return GoogleTokens(accessToken: response.access_token,
                            refreshToken: response.refresh_token ?? tokens.refreshToken,
                            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)))
    }

    /// Best effort: tells Google to forget this app's access.
    public func revoke(_ token: String) async {
        var request = URLRequest(url: Self.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([("token", token)])
        _ = try? await transport.send(request)
    }

    // MARK: Internals

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
    }
    private struct TokenError: Decodable { let error: String?; let error_description: String? }

    private func tokenRequest(_ fields: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)
        let (data, http) = try await transport.send(request)
        guard http.statusCode == 200 else {
            let err = try? JSONDecoder().decode(TokenError.self, from: data)
            // invalid_grant = refresh token revoked/expired: the user must sign in again.
            if err?.error == "invalid_grant" { throw MailProviderError.notAuthorized }
            throw MailProviderError.network(err?.error_description ?? "Google sign-in failed (\(http.statusCode)).")
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw MailProviderError.network("Unreadable response from Google.")
        }
        return decoded
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}

/// Owns one account's tokens: reads them from the Keychain, refreshes when they
/// are about to expire, and serialises refreshes (it is an actor).
public actor GoogleTokenManager {
    private let auth: GoogleAuth
    private let secrets: SecretStore
    private let key: String

    public static func keychainKey(for accountID: UUID) -> String { "\(accountID.uuidString).google" }

    public init(accountID: UUID, auth: GoogleAuth, secrets: SecretStore) {
        self.auth = auth
        self.secrets = secrets
        self.key = Self.keychainKey(for: accountID)
    }

    public func save(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try secrets.set(String(decoding: data, as: UTF8.self), for: key)
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard var tokens = try load() else { throw MailProviderError.notAuthorized }
        if forceRefresh || tokens.expiresAt.timeIntervalSinceNow < 60 {
            tokens = try await auth.refresh(tokens)
            try save(tokens)
        }
        return tokens.accessToken
    }

    /// Revokes access at Google (best effort) and deletes local tokens.
    public func signOut() async {
        if let tokens = try? load() { await auth.revoke(tokens.refreshToken) }
        secrets.remove(key)
    }

    private func load() throws -> GoogleTokens? {
        guard let json = try secrets.get(key) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: Data(json.utf8))
    }
}
