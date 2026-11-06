# Inbox Butler

A personal email assistant for iPhone and iPad. It merges several mailboxes into
one inbox and does the admin for you: it reads attachments, proposes calendar
events, drafts replies in your own writing style, and surfaces what matters in a
widget.

> **Status: scaffold.** The app shell and widget run on mock data. No real mail provider is
> wired up yet. See [ARCHITECTURE.md](ARCHITECTURE.md) for the plan and open questions.

## Repository layout

```
project.yml             XcodeGen spec: generates InboxButler.xcodeproj (app + widget)
InboxButlerCore/        Local Swift package: all shared logic (models, providers,
                        sync, AI protocol, style profile, widget snapshot). No UI.
InboxButler/            The iOS app target (SwiftUI).
InboxButlerWidget/      WidgetKit extension (small, medium, lock screen).
README.md
ARCHITECTURE.md
```

Target: **Xcode, iOS 17+, distributed through TestFlight.**

## Building (Mac with Xcode 15+)

```bash
brew install xcodegen
xcodegen generate
open InboxButler.xcodeproj
```

Before the first build, replace the placeholders (all in `project.yml` unless noted):

| Placeholder | Where |
|---|---|
| `DEVELOPMENT_TEAM` (your team id) | `project.yml` |
| `com.example.InboxButler` (bundle id); widget must be `<app id>.Widget` | `project.yml` |
| `group.com.example.InboxButler` (App Group) | `project.yml` (both targets) **and** `WidgetSnapshotStore.appGroupID` in Core |

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

## What leaves the device

| Data | Leaves the device? | Where / why |
|---|---|---|
| Mail content (headers, bodies, attachments) | Only to your own mail provider | Fetched over TLS from Google, Microsoft, iCloud or your IMAP server. Nothing is copied anywhere else. |
| OAuth tokens, app passwords | **No** | iOS Keychain only. Never written to disk, logs or the App Group. |
| Local mail cache, style profile, widget snapshot | **No** | App sandbox / App Group container on the device. |
| Style profile (learned from sent mail) | **No** | Computed on-device and stored locally. |
| Summaries, importance, date extraction, drafting | **Depends on the AI choice (undecided)** | Option A, Apple Foundation Models: nothing leaves the device. Option B, backend proxy: the text sent for each request leaves the device and goes to your proxy and then the model provider. Not implemented until you choose. |
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
