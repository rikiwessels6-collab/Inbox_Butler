# Inbox Butler

A personal email assistant for iPhone and iPad. It merges several mailboxes into
one inbox and does the admin for you: it reads attachments, proposes calendar
events, drafts replies in your own writing style, and surfaces what matters in a
widget.

> **Status: scaffold.** The app shell runs on mock data. No real mail provider is
> wired up yet. See [ARCHITECTURE.md](ARCHITECTURE.md) for the plan and open questions.

## Repository layout

```
InboxButlerCore/        Local Swift package: all shared logic (models, providers,
                        sync, AI protocol, style profile, widget snapshot).
                        Builds in Swift Playgrounds *and* Xcode.
InboxButler.swiftpm/    The app, as a Swift Playgrounds-compatible package.
                        SwiftUI only; depends on InboxButlerCore.
Widget/                 WidgetKit extension sources. NOT part of the .swiftpm
                        (Swift Playgrounds cannot build extensions). Xcode only.
README.md
ARCHITECTURE.md
```

## Building

### Swift Playgrounds (iPad)
1. Put the whole repo somewhere Playgrounds can open (iCloud Drive or Files).
2. Open `InboxButler.swiftpm`.
3. It depends on `../InboxButlerCore` by relative path. If Playgrounds will not
   resolve a local path dependency, see "Open questions" in ARCHITECTURE.md
   (fallback: reference the Core package by Git URL).
4. Run. You get the account list and a unified inbox with mock data.

### Xcode (Mac)
1. Open `InboxButler.swiftpm` directly in Xcode (it opens as a package app), or
   create an iOS App project and add `InboxButlerCore` as a local package.
2. Widget setup is **Xcode only**, see below.

## Enabling the widget (Xcode only)

Swift Playgrounds cannot build widget extensions, so the widget lives outside the
`.swiftpm`. The app works fine without it. To turn it on you need a Mac with Xcode
and a paid Apple Developer account (App Groups need one):

1. Create an Xcode project (iOS App, SwiftUI) and drag in the contents of
   `InboxButler.swiftpm` (or keep using the package app and add it to a
   workspace; an Xcode project is simpler for extensions).
2. Add the local package `InboxButlerCore` to the project.
3. **File > New > Target > Widget Extension**. Name it `InboxButlerWidget`.
   Untick "Include Live Activity" and "Include Configuration App Intent".
4. Delete the generated Swift files and add the files from `Widget/InboxButlerWidget/`
   to that target. Also link `InboxButlerCore` to the widget target.
5. Signing & Capabilities, on **both** the app target and the widget target:
   add **App Groups** and tick the same group, e.g. `group.<your.bundle.id>`.
6. Set that group id in `WidgetSnapshotStore.appGroupID`
   (`InboxButlerCore/Sources/InboxButlerCore/Widget/WidgetSnapshot.swift`).
7. Run the app once so it writes a snapshot, then add the widget from the
   Home Screen / Lock Screen widget gallery.

The app never talks to the widget directly. It writes a small JSON snapshot into
the shared App Group container and asks WidgetKit to reload timelines. The widget
only reads that file.

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
