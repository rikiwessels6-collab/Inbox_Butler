import InboxButlerCore

/// Settings you must fill in once. None of these are secrets.
enum AppConfig {
    /// iOS OAuth client ID from Google Cloud Console (see docs/SETUP_GOOGLE.md).
    /// Looks like "1234567890-abcdefg.apps.googleusercontent.com".
    static let googleClientID = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"

    static var googleOAuth: GoogleOAuthConfig { GoogleOAuthConfig(clientID: googleClientID) }
}
