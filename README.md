# Inbox Butler

A personal email assistant for iPhone and iPad. It merges several mailboxes into
one inbox and does the admin for you: it reads attachments, proposes calendar
events, drafts replies in your own writing style, and surfaces what matters in a
widget.

> **Status: Gmail works (read-only), other providers are stubs.** With no account connected
> the app shows demo data. See [docs/SETUP_GOOGLE.md](docs/SETUP_GOOGLE.md) to connect Gmail.
> See [ARCHITECTURE.md](ARCHITECTURE.md) for the plan and open questions.

## Repository layout

```
project.yml             XcodeGen spec: generates InboxButler.xcodeproj (app + widget)
InboxButlerCore/        Local Swift package: all shared logic (models, providers,
                        sync, AI protocol, style profile, widget snapshot). No UI.
InboxButler/            The iOS app target (SwiftUI).
InboxButlerWidget/      WidgetKit extension (small, medium, lock screen).
README.md
ARCHITECTURE.md
docs/SETUP_GOOGLE.md   One-time Google Cloud setup for Gmail sign-in
```

Target: **Xcode, iOS 17+, distributed through TestFlight.**

## Building (Mac with Xcode 15+)

```bash
brew install xcodegen
xcodegen generate
open InboxButler.xcodeproj
```

Bundle ids are set for Boundary Line Apps. Before the first build, set your team id and (if you change the ids) keep these in sync (all in `project.yml` unless noted):

| Placeholder | Where |
|---|---|
| `DEVELOPMENT_TEAM` (your team id, **still to fill in**) | `project.yml` |
| `com.boundarylineapps.InboxButler` (bundle id); widget must be `<app id>.Widget` | `project.yml` |
| `group.com.boundarylineapps.InboxButler` (App Group) | `project.yml` (both targets) **and** `WidgetSnapshotStore.appGroupID` in Core |

Then in the Apple Developer portal register the App Group and both bundle ids
(Xcode's automatic signing does this for you once the team is set). Run on a
device or simulator: you get the account list and a unified inbox on mock data,
and the widget fills from the same data.

Run the Core tests with `cd InboxButlerCore && swift test` (or in Xcode).

If you would rather not use XcodeGen, create an iOS App + Widget Extension in
Xcode by hand, add `InboxButlerCore` as a local package, and drag in the two
source folders. `project.yml` documents the exact settings and entitlements.

## TestFlight checklist

1. Paid Apple Developer Program membership.
2. Set the placeholders above; register the App Group.
3. Add a 1024x1024 icon to `InboxButler/Assets.xcassets/AppIcon.appiconset`.
4. In App Store Connect, create the app record with your bundle id.
5. Xcode: Product > Archive > Distribute App > TestFlight.
6. Internal testers (up to 100, members of your team) get builds immediately.
   External testers require a short Beta App Review.
7. Export compliance: `ITSAppUsesNonExemptEncryption` is set to `false` because the app
   only uses OS-provided HTTPS. Confirm that stays true.
8. Privacy: `PrivacyInfo.xcprivacy` is included (no tracking, no collected data). If an
   AI proxy is added, revisit it and the App Privacy answers.

## Attachments and calendar events

Open a message and the app reads it **on your device**:
- the full message text (plain text, or HTML converted to text);
- **PDFs** (text layer; scanned PDFs are read with on-device OCR, first 3 pages),
  **images** (on-device OCR), **Word `.docx`**, and **calendar invites (`.ics`)**;
- up to 5 attachments per message, each up to 15 MB. Old `.doc` files are not supported.

Dates found become **suggested events** with the sentence they came from. You can
edit the title and time, then tap **Add to Calendar** or **Dismiss**. Nothing is added
without your tap, and a dismissed or added event never comes back.

- **Write-only calendar access:** iOS lets the app add events but not read or change
  anything already in your calendar.
- New unread mail from **priority senders** is scanned automatically (max 5 per refresh)
  so today's events can reach the widget. Other mail is scanned only when you open it.
- Attachments are downloaded from your own mail server, scanned in memory and thrown away.

**Known limits** (it is a heuristic until the AI layer is added):
- Date finding uses Apple's date detector. It can miss events or suggest wrong ones, so
  always check the evidence line.
- Relative dates ("tomorrow", "next Friday") are worked out from *today*, not from the
  day the email was sent, so they can be wrong on older mail.
- Recurring invites propose only the first occurrence.

## Priority senders and notifications

- You choose the senders (a full address, or `@company.com` for everyone at a
  company) in the **Priority** tab, or from any message ("Notify me about ...").
- **Only** mail from those senders sends a notification. It shows the sender,
  account and subject. Everything else stays silent.
- The widget pins priority mail first (starred), then other urgent mail, today's
  events and replies waiting. Lock Screen widget included.
- Notifications are **local**: generated on the device from mail it already
  downloaded. No push server and no data leaves the device for them.
- **Limit:** without a server, iOS only wakes the app to check mail occasionally
  (Background App Refresh, usually 15+ minutes, less if you rarely open the app or
  Low Power Mode is on). Alerts are therefore not instant. Truly real-time alerts
  need a small push backend (see ARCHITECTURE.md, "Real-time notifications").
- Installing the app (or turning notifications on) never floods you with old mail:
  existing mail is recorded silently first.

## What leaves the device

| Data | Leaves the device? | Where / why |
|---|---|---|
| Mail content (headers, bodies, attachments) | Only to your own mail provider | Fetched over TLS from Google, Microsoft, iCloud or your IMAP server. Nothing is copied anywhere else. |
| OAuth tokens, app passwords | **No** | iOS Keychain only. Never written to disk, logs or the App Group. |
| Attachments (PDF, images, docs) | Only from your mail server to the device | Downloaded, read with on-device PDFKit / Vision OCR, then discarded. |
| Calendar events you add | **No** | Written to your on-device calendar with write-only access. |
| Local mail cache, style profile, widget snapshot | **No** | App sandbox / App Group container on the device. |
| Style profile (learned from sent mail) | **No** | Computed on-device and stored locally. |
| Summaries, importance, date extraction, drafting | **Depends on the AI choice (undecided)** | Option A, Apple Foundation Models: nothing leaves the device. Option B, backend proxy: the text sent for each request leaves the device and goes to your proxy and then the model provider. Not implemented until you choose. |
| Notification text (sender, subject) | **No** | Local notifications built on the device. On a locked device iOS may show or hide previews per your Notification settings. |
| Analytics / telemetry | **None** | There is none. |

No API key is ever embedded in the app.

## Safety rules the code enforces

- **Read-only first.** `MailProvider` has no send, delete, archive or move
  method. Gmail and Microsoft start with read-only scopes only.
- **Drafts are never sent automatically.** A draft is a local object you review.
  Sending will be a separate, explicitly user-triggered step added later.
- **Calendar events are proposals** until you confirm each one.

## Private TestFlight, not App Store (for now)

Gmail full-mailbox access uses a *restricted* scope. Public release needs Google
OAuth verification plus a third-party security assessment. For now the app is
designed for private use and TestFlight. Steps are listed in ARCHITECTURE.md.
