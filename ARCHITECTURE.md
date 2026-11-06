# Inbox Butler: Architecture

## Goals and constraints

- Xcode project (generated from `project.yml`), distributed via **TestFlight**.
- All shared logic in a separate local package, `InboxButlerCore`, shared by the
  app and the widget extension.
- Widget extension is its own target; data is shared via an App Group.
- Offline-first, SwiftData, secrets in Keychain only.
- Read-only mail access first. Never send/delete/archive without explicit user action.
- On-device processing where possible. No API keys in the app.

## Package layout

```
InboxButlerCore  (library, iOS 17+/macOS 14+, no UI)
  Accounts/      MailAccount, AccountKind, KeychainStore
  Mail/          MailMessage, AttachmentInfo, MailProvider protocol, Mailbox,
                 SyncCursor, errors
  Providers/     GmailProvider, MicrosoftProvider, IMAPProvider (stubs),
                 MockMailProvider (working, for the shell and tests)
  Sync/          SyncEngine: fans out to providers, merges into one list
  AI/            AIService protocol, ImportanceScore, UnconfiguredAIService
  Calendar/      EventProposal, CalendarWriter protocol
  StyleProfile/  StyleProfile, StyleProfileStore (local JSON)
  Drafts/        ReplyDraft (local only; no send path)
  Widget/        WidgetSnapshot + WidgetSnapshotStore (App Group JSON)

InboxButler  (app target, SwiftUI)
  App entry, AppModel, AccountListView, UnifiedInboxView, MessageDetailView

InboxButlerWidget  (widget extension; reads WidgetSnapshot)
```

## Module plan

| Module | Responsibility | State |
|---|---|---|
| Accounts | Account list, sign-in flows, credentials in Keychain | Models + Keychain done; sign-in stubs |
| Sync | Per-account incremental sync, merge, dedupe, errors per account | Engine done against mock |
| Inbox | Unified list, account badge, read state | UI done on mock data |
| Attachments | Download on demand; PDF (PDFKit), images (Vision OCR), `.ics`, Word (`.docx` is zipped XML) text extraction | Planned |
| Calendar | Turn extracted dates into `EventProposal`; EventKit write only after user confirms | Protocol only |
| StyleProfile | Learn tone, greeting/sign-off, length, phrases from Sent mail, on-device; store locally | Model + store only |
| Drafts | Generate reply with style profile; user reviews; never auto-sent | Model only |
| Widget | Snapshot written by app, read by WidgetKit extension | Snapshot builder, app publisher and widget done (mock data) |
| AI | `AIService` protocol: summary, importance, event extraction, drafting | Protocol + "not configured" stub |

### Provider abstraction

```swift
public protocol MailProvider: Sendable {
    var account: MailAccount { get }
    func authorize() async throws
    func fetchMessages(in: Mailbox, since: SyncCursor?, limit: Int) async throws -> MailPage
    func fetchAttachment(_ info: AttachmentInfo, in: MailMessage) async throws -> Data
}
```

Deliberately there is **no** send/delete/archive/move requirement. Adding any
mutating capability later means adding a new, separate protocol that the UI only
calls from an explicit user action.

### Storage (planned)

SwiftData models mirror `MailMessage` (`StoredMessage`) plus extracted events and
drafts. The app reads the UI from SwiftData and the SyncEngine writes into it, so
the inbox works offline. Deferred until the first real provider lands, so the
schema is shaped by real data rather than guessed. Tokens and passwords never go
into SwiftData; Keychain only (`KeychainStore`).

### Widget data flow

App sync -> `WidgetSnapshot.make(...)` (urgent emails, today's events, replies
waiting) -> write JSON to App Group container -> `WidgetCenter.reloadAllTimelines()`.
The widget extension only reads. Snapshots hold subjects and sender names; if you
would rather keep even those off the Lock Screen, the widget can show counts only
(open question 7).

## Provider notes

### Gmail
- Scope: `https://www.googleapis.com/auth/gmail.readonly` (restricted scope).
- OAuth with PKCE via `ASWebAuthenticationSession`. iOS OAuth client type, no client secret.
- **Avoiding weekly re-sign-in:** refresh tokens expire after **7 days** only while the
  consent screen is in "Testing". Publish it to **"In production"** (External) *without*
  submitting for verification: tokens then persist. You get a one-time "unverified app"
  warning and a 100-user cap, fine for private use. Tokens can still be revoked (password
  change, manual revoke, ~6 months unused). Confirm current Google rules in the console.
- **Fallback:** Gmail over IMAP with an app password (needs 2-step verification, no OAuth,
  no expiry; loses labels/threads).

### Microsoft (Outlook / Hotmail)
- Microsoft identity platform v2 + Microsoft Graph. Scopes: `Mail.Read`,
  `offline_access`, `User.Read`. Add `Calendars.Read` only if ever needed (not planned).
- Register a public client app in Entra ID with a custom redirect URI.
- Personal accounts need "Accounts in any organizational directory and personal Microsoft accounts".

### iCloud
- IMAP `imap.mail.me.com:993` (TLS) with an **app-specific password** generated at
  appleid.apple.com. Stored in Keychain.

### Generic IMAP
- Host/port/TLS/username/password. Same code path as iCloud.
- Foundation has no IMAP client. Needs a library or a small client on `Network.framework`
  (open question 3).

## Privacy model

Everything runs on the device except traffic to your own mail servers and, if you
choose the proxy option, AI requests. See the table in README.md. Rules:
1. No API key in the app binary. Ever.
2. Tokens/passwords in Keychain only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
   so background sync works but they do not migrate to other devices).
3. The AI layer reports where it processes (`AIProcessingLocation`) so the UI can
   show it.
4. No analytics.

## Gmail: steps for private TestFlight use

1. Create a Google Cloud project; enable the Gmail API.
2. Configure the OAuth consent screen: External. Start in Testing with your own address
   as a test user, then **Publish app** (In production, unverified) to stop the 7-day expiry.
3. Add the `gmail.readonly` scope.
4. Create an OAuth client of type **iOS** with your bundle id; note the client id and
   reversed-client-id URL scheme.
5. Sign in from the app; accept the "unverified app" warning.
6. If you stay in Testing mode, expect weekly re-auth.
7. TestFlight: see the checklist in README.md. Internal testing needs no Beta App
   Review, which suits private use.

**For a public release (not planned):** move consent screen to Production, submit
for OAuth verification, and pass the annual CASA security assessment required for
restricted scopes (cost and effort are significant), plus a privacy policy and a
demo video. Ask whether you want to pursue this before investing.

## Open questions (need your decision)

1. **AI layer: on-device Apple Foundation Models, or a small backend proxy?**
   - *Foundation Models:* nothing leaves the device, no server to run, no key.
     Needs an Apple-Intelligence-capable iPad/iPhone on a recent OS, and a smaller
     context window than cloud models (long PDFs need chunking). Quality for
     drafting in your style is more limited.
   - *Proxy:* better quality and long-document handling, but mail text leaves the
     device, and you must host/secure a server (auth, rate limits, no logging).
   - Hybrid is possible (on-device first, proxy opt-in per account). I have **not**
     implemented either; only the protocol exists.
2. **First provider to wire up.** Suggested: Gmail (REST API, simple JSON, easiest).
3. **IMAP library.** Now that third-party packages are fine: use `swift-nio-imap`
   (parser/codec only, you still write the connection and session logic) or write a
   minimal client on `Network.framework`? I lean towards `swift-nio-imap`.
4. **Bundle id, team id and App Group id.** Placeholders (`com.example.InboxButler`,
   `group.com.example.InboxButler`) are in `project.yml` and Core.
5. **Project generation.** I used XcodeGen (`project.yml`) because I cannot author a
   reliable `.xcodeproj` from Linux. If you prefer a committed `.xcodeproj`, generate
   it once on your Mac and commit it.
6. **OAuth sign-in.** Google and Microsoft will use `ASWebAuthenticationSession` with
   PKCE and a custom URL scheme per provider (added to the app's Info.plist when that
   provider is wired up).
7. **Widget privacy.** Show sender/subject on the Lock Screen, or counts only?
8. **Minimum OS.** Currently iOS 17 (SwiftData, Observation, interactive widgets).
   Foundation Models would need iOS 26 for that code path (guarded with `#available`).
9. **Mail you reply to.** Drafts stay in-app. Later: save as a provider draft
   (needs `gmail.compose`), or hand off via a `mailto:`/share sheet. Which?

## Build order proposal

1. Scaffold + mock shell + widget (done).
2. First real provider (your pick), with SwiftData cache and Keychain tokens.
3. Remaining providers.
4. Attachment text extraction + event proposals + EventKit confirm flow.
5. Style profile learning + drafts.
6. Widget fed by real data (publisher already in place).
7. AI layer implementation (after you choose).

> Note: the code in this repo was written without a Swift toolchain available, so
> it has not been compiled yet. Expect a few small compile fixes on first build.
