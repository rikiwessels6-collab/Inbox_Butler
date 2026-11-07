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
| Accounts | Account list, sign-in flows, credentials in Keychain | Gmail sign-in (PKCE, read-only) done; others stubbed |
| Sync | Per-account sync, merge, dedupe, errors per account, SwiftData offline cache | Done for Gmail (re-reads newest 50; historyId incremental sync later) |
| Inbox | Unified list, account badge, read state | UI done on mock data |
| Attachments | Download on demand; PDF (PDFKit), images (Vision OCR), `.ics`, Word `.docx` text extraction; `fetchBody` for message text | Done (on-device, no AI) |
| Calendar | Turn extracted dates into `EventProposal`; EventKit write only after user confirms | Done: `ICSParser`, `DateEventExtractor`, `EventProposalStore`, full-access `EventKitCalendarWriter` (calendar picker, overlap + duplicate hints, never blocks) |
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

### Storage

`MessageCache` (SwiftData, `StoredMessage`) mirrors `MailMessage`. At launch the UI
shows the cache instantly; a refresh updates it per account (a failing/offline
account keeps its cached mail). Accounts (no secrets) are in `Accounts.json`.
Extracted events and drafts get SwiftData models when those modules land. Tokens and passwords never go
into SwiftData; Keychain only (`KeychainStore`).

### Widget data flow

App sync -> `WidgetSnapshot.make(...)` (urgent emails, today's events, replies
waiting) -> write JSON to App Group container -> `WidgetCenter.reloadAllTimelines()`.
The widget extension only reads. Snapshots hold subjects and sender names; if you
would rather keep even those off the Lock Screen, the widget can show counts only
(open question 7).

## Priority senders, notifications and widget

- `PrioritySender` rules (address or `@domain`), stored locally as JSON.
- `NotificationPlanner` (pure, tested): unread + priority sender + not already
  notified, max 5 per run. `NotifiedStore` prevents duplicates; the first run seeds
  silently.
- `NotificationService` posts local notifications (title = sender, subtitle =
  account, body = subject).
- `BackgroundRefresh` schedules `BGAppRefreshTask`. iOS controls timing.
- `WidgetSnapshot.make` ranks priority-sender mail first, then importance.

### Real-time notifications (decision needed later)
Local notifications cannot fire the moment mail arrives, because iOS only wakes the
app occasionally. Real-time needs a server that is told about new mail and sends an
APNs push:
- Gmail: `users.watch` -> Cloud Pub/Sub -> your server -> APNs.
- Microsoft: Graph change-notification subscriptions -> your server -> APNs.
- IMAP/iCloud: server holds IMAP IDLE connections (needs stored credentials server-side).
The server must see mail metadata (and hold tokens) for this, which conflicts with
"nothing leaves the device". A privacy-preserving variant: the server stores only
refresh tokens and the priority list, and pushes a silent "check now" wake-up, with
the app fetching and writing the notification text locally (Notification Service
Extension). The same server could host the AI proxy. Not built; decide when
reliability of alerts matters more than the extra infrastructure.

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

1. **AI layer** *(decided: hybrid, on-device first; proxy optional later. Not yet implemented.)*
   - *Foundation Models:* nothing leaves the device, no server to run, no key.
     Needs an Apple-Intelligence-capable iPad/iPhone on a recent OS, and a smaller
     context window than cloud models (long PDFs need chunking). Quality for
     drafting in your style is more limited.
   - *Proxy:* better quality and long-document handling, but mail text leaves the
     device, and you must host/secure a server (auth, rate limits, no logging).
   - Hybrid is possible (on-device first, proxy opt-in per account). I have **not**
     implemented either; only the protocol exists.
2. **First provider** *(decided: Gmail.)*
3. **IMAP library** *(decided: `swift-nio-imap`.)*
4. **Bundle id and App Group id** *(decided: `com.boundarylineapps.InboxButler`, widget `.Widget`, group `group.com.boundarylineapps.InboxButler`.)* Team id still to fill in `project.yml`.
5. **Project generation.** I used XcodeGen (`project.yml`) because I cannot author a
   reliable `.xcodeproj` from Linux. If you prefer a committed `.xcodeproj`, generate
   it once on your Mac and commit it.
6. **OAuth sign-in.** Google and Microsoft will use `ASWebAuthenticationSession` with
   PKCE and a custom URL scheme per provider (added to the app's Info.plist when that
   provider is wired up).
7. **Widget privacy** *(decided: show sender and subject.)* Note Lock Screen widgets are visible on a locked device; iOS can redact them under Settings > Face ID & Passcode.
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
