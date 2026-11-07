import InboxButlerCore

/// Settings you must fill in once. None of these are secrets.
enum AppConfig {
    /// iOS OAuth client ID from Google Cloud Console (see docs/SETUP_GOOGLE.md).
    /// Looks like "1234567890-abcdefg.apps.googleusercontent.com".
    static let googleClientID = "1025660268612-304r55pkjvs8hp1tj4vjf3bak23cgg39.apps.googleusercontent.com"

    static var googleOAuth: GoogleOAuthConfig { GoogleOAuthConfig(clientID: googleClientID) }
}
