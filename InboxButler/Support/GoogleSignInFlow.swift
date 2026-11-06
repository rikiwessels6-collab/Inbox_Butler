import AuthenticationServices
import UIKit
import InboxButlerCore

enum SignInError: LocalizedError {
    case cancelled
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .failed(let message): return message
        }
    }
}

/// Shows Google's sign-in page in the system web sheet (ASWebAuthenticationSession)
/// and returns tokens. The app never sees your Google password.
@MainActor
final class GoogleSignInFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn(config: GoogleOAuthConfig) async throws -> GoogleTokens {
        let auth = GoogleAuth(config: config)
        let pkce = PKCE()
        let state = UUID().uuidString
        let url = auth.authorizationURL(pkce: pkce, state: state)

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SignInError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SignInError.failed("Sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: SignInError.failed("Could not open the sign-in page."))
            }
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? SignInError.cancelled : SignInError.failed("Google said: \(error)")
        }
        // The state must match what we sent, or the response is not ours.
        guard value("state") == state, let code = value("code") else {
            throw SignInError.failed("Unexpected response from Google.")
        }
        return try await auth.exchange(code: code, pkce: pkce)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
