import Foundation
import CryptoKit

/// PKCE (RFC 7636): lets a public app (no client secret) sign in safely.
/// The verifier stays in the app; only its hash (challenge) goes in the sign-in URL.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init() {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }   // system CSPRNG
        self.init(verifier: Self.base64URL(Data(bytes)))
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
