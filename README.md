# Inbox Butler

A personal email assistant for iPhone and iPad. It merges several mailboxes into
one inbox and does the admin for you: it reads attachments, proposes calendar
events, drafts replies in your own writing style, and surfaces what matters in a
widget.

> **Status: Gmail and iCloud Mail (read-only) are built; Outlook is not yet.** With no account connected
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

## TestFlight without a Mac

The repo builds on GitHub's cloud Macs (`.github/workflows/ci.yml` runs on every push and
checks the app compiles and the tests pass). To send a build to TestFlight from your iPad,
follow **[docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)**.

## TestFlight checklist (if building on a Mac yourself)

1. Paid Apple Developer Program membership.
2. Set the placeholders above; register the App Group.
3. A placeholder icon is included; replace `icon.png` in `InboxButler/Assets.xcassets/AppIcon.appiconset` with your own.
4. In App Store Connect, create the app record with your bundle id.
5. Xcode: Product > Archive > Distribute App > TestFlight.
6. Internal testers (up to 100, members of your team) get builds immediately.
   External testers require a short Beta App Review.
7. Export compliance: `ITSAppUsesNonExemptEncryption` is set to `false` because the app
   only uses OS-provided HTTPS. Confirm that stays true.
8. Privacy: `PrivacyInfo.xcprivacy` is included (no tracking, no collected data). If an
   AI proxy is added, revisit it and the App Privacy answers.

## The Superhuman-style experience (all on-device)

- **Welcome and guided tour.** A full-bleed landscape sign-in, then a short tour with practice emails
  you can really swipe, an overview of the assistant, and an optional "help it sound like you" step.
- **Swipe triage.** Swipe **right** to set a reminder (the email leaves the inbox and returns at the top,
  with a notification), swipe **left** to mark it **Done**. Both have an **Undo** banner. Reminders and
  Done each have their own list.
  **Important:** this is app-only. Your real mailbox is never touched, so mail stays in Gmail/iCloud
  exactly where it was; it just disappears from Inbox Butler until it's due or you restore it. This is
  deliberate: the app has no permission to archive, delete or move your mail.
- **Automatic labels.** Each email gets up to two coloured labels (Security, Invoice, Receipt, Travel,
  Appointment, Meeting, Delivery, To review, Newsletter) from quick on-device rules over the subject,
  preview and attachments. They're keyword rules, not AI, so they're instant and work offline.
- **Important / Other / Newsletters split**, plus Needs a reply, Drafts, Reminders and Done.
- **Calendar tab.** Your real week from every calendar on the device (iCloud, Google, family). Overlapping
  events sit side by side, so double-bookings stay visible. Events found in your email appear as dashed
  suggestions. Read for display only; nothing is stored or sent.
- **Search tab.** Search every account at once, offline, with filters and recent searches.
- **"All caught up"** shows a landscape instead of an empty list.

## Inbox, search and reply tracking

- **iPad split view** (filters, list, message) that collapses to a normal stack on iPhone.
- Filters: **All, Priority, Needs a reply, Waiting on others, Newsletters**, plus one per account.
  Search covers every account and works offline.
- **Needs a reply / Waiting on others** are worked out on-device from your inbox and sent mail.
  Limit: it only sees mail still in the Inbox, so archiving a reply in Gmail can cause a false
  "no reply yet" reminder.
- **Follow-up reminders** only fire for mail you sent to a *priority* contact (default on).
- **Suggested priority senders** from your own habits (people you write to often and answer
  quickly). Nothing is added unless you tap Add.
- **Time Sensitive** priority notifications (can break through Focus), optional **8:00 morning
  summary**, optional **Face ID lock**, optional **hide sender/subject on widgets**.
- **Siri / Shortcuts:** "What's urgent in Inbox Butler?" reads the same summary as the widget.
- **View formatted** shows the original HTML: JavaScript off, remote images/trackers blocked
  unless you tap "Load remote images", links open in Safari. Attachments preview with Quick Look
  (temporary copy deleted afterwards).

## Attachments and calendar events

Open a message and the app reads it **on your device**:
- the full message text (plain text, or HTML converted to text);
- **PDFs** (text layer; scanned PDFs are read with on-device OCR, first 3 pages),
  **images** (on-device OCR), **Word `.docx`**, and **calendar invites (`.ics`)**;
- up to 5 attachments per message, each up to 15 MB. Old `.doc` files are not supported.

Dates found become **suggested events** with the sentence they came from. You can
edit the title and time, then tap **Add to Calendar** or **Dismiss**. Nothing is added
without your tap, and a dismissed or added event never comes back.

- **Full calendar access (you choose to allow it):** pick which calendar each event goes to
  (iCloud, shared family, Google). Overlaps are shown as information and **never block or skip
  an add**; an event that already looks to be in the calendar is flagged so it isn't doubled.
  The app only looks at events around the one you're adding, and nothing is stored or sent.
- **Google calendars:** add your Google account in iOS Settings > Calendar > Accounts with
  Calendars switched on. Its calendars then appear in the app and events sync to Google.
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
| Calendar events you add | **No** | Written to your on-device calendar. Existing events are read only to show overlaps and are never stored or sent. |
| Local mail cache, style profile, widget snapshot | **No** | App sandbox / App Group container on the device. |
| Style profile (learned from sent mail) | **No** | Computed on-device and stored locally. |
| Drafting replies | **No by default. Yes only if you turn on Cloud drafts** | Default: Apple Intelligence on the phone, or a built-in template, so nothing leaves the device. If you switch on Cloud drafts in Settings and add your own Anthropic API key, tapping "Draft a reply" sends that one email, plus a short summary of your writing style, to Anthropic's API over HTTPS. Your key is stored in the iOS Keychain, not in the app. Nothing is sent until you tap, and drafts are never sent as email without you tapping Send. |
| Summaries, importance, date extraction | **No** | Done on the device by simple rules. |
| Notification text (sender, subject) | **No** | Local notifications built on the device. On a locked device iOS may show or hide previews per your Notification settings. |
| Analytics / telemetry | **None** | There is none. |

No API key is ever embedded in the app. (If you choose Cloud drafts, your own key is kept only in your phone's Keychain.)

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
