# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Inbox Butler: a SwiftUI iOS 17+ app (Boundary Line Apps) that merges Gmail, iCloud/generic IMAP (Outlook is a stub) into one inbox, proposes calendar events from attachments, drafts replies in the user's voice on-device, with a widget and priority-sender notifications. Distributed via **TestFlight only**. The owner has no Mac: everything is built and verified on GitHub Actions macOS runners, and this Linux environment has **no Swift toolchain**, so code cannot be compiled locally. Verify through CI.

## Commands

- Core tests (macOS only): `cd InboxButlerCore && swift test` (single test: `swift test --filter TriageTests/testName`).
- App project is generated, not committed: `brew install xcodegen && xcodegen generate`, then `xcodebuild build -project InboxButler.xcodeproj -scheme InboxButler -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- UI tests: scheme `InboxButler`, `-only-testing:InboxButlerUITests`, destination iPhone 16 simulator.
- CI (`.github/workflows/ci.yml`, on push to `master`): Core tests, app+widget build on Xcode 26, "basic" build (no widget), simulator UI smoke test. Check results with the GitHub MCP tools (`actions_list`, `get_job_logs`).
- TestFlight: dispatch `.github/workflows/testflight.yml` (input `include_widget`, default false for the "basic" build). It archives unsigned and signs at export with the App Store Connect API key stored in GitHub secrets. Never paste that key into chat or files.
- Workflow steps capture exit status (`&& status=0 || status=$?`) rather than piping through `tail`, which would mask failures; keep that pattern.

## Architecture

- `project.yml` (XcodeGen) defines targets: `InboxButler` (app), `InboxButlerWidget`, `InboxButlerUITests`. `DEVELOPMENT_TEAM` is empty in the repo and injected in CI. `scripts/make_basic_project.py` strips the widget target and the App Group / Time Sensitive entitlements for the basic TestFlight build (those need extra Apple portal setup, see `docs/TESTFLIGHT.md`).
- **`InboxButlerCore`** (local Swift package, no UI) holds all logic and is what the tests cover: providers (`MailProvider` protocol, `GmailProvider` REST+PKCE, custom read-only `IMAPProvider`/`IMAPClient` on NWConnection, `MockMailProvider`), `SyncEngine`, SwiftData `MessageCache`, Keychain-only secrets, attachment text extraction, event extraction and EventKit writer, priority/notification planning, style learning and drafts, app-only triage, `WidgetSnapshot`.
- **`InboxButler/`** (SwiftUI app): `AppModel` is the single `@Observable @MainActor` singleton wiring accounts, sync, triage, drafts, calendar, notifications and widget publishing; views read from it. The widget only reads a JSON snapshot from the App Group.
- iOS 26 / Apple Intelligence code (`OnDeviceAIService`, FoundationModels) is guarded with `#available` / `#if canImport(FoundationModels)` and falls back to `TemplateDraftService`. Swift 5.9 language mode.

## Hard rules (the product's safety guarantees)

- **Mailbox access is read-only.** `MailProvider` has no send/delete/archive/move; IMAP uses EXAMINE + BODY.PEEK only; Gmail scope is `gmail.readonly`. Adding any mutating capability needs a separate protocol, triggered only by explicit user action, and the user's confirmation first.
- **Done and Remind-me are app-only** (`TriageStore`); they never touch the real mailbox.
- Drafts are never auto-sent; replies go through `MFMailComposeViewController` and the user taps Send.
- Calendar events are proposals confirmed by the user; overlaps are informational and must never block an add.
- No API keys in the app; tokens/passwords only in Keychain. Process on-device; no analytics. Update the README "What leaves the device" table if that changes.
- Email text is untrusted input to the on-device model (see `DraftPrompt`).

## Gotchas

- Swift string escapes and CI-only failures: you cannot compile here, so re-read edits carefully (past breakages: invalid `"\;"` escape, duplicate variable names).
- UI tests launch with `-hasSeenWelcome YES -hasSeenTour YES` and rely on `accessibilityIdentifier`s (`welcome-*`, `tour-*`); overlays use `.accessibilityAddTraits(.isModal)`. Keep those stable when editing views.
- Google OAuth consent screen is in Testing mode (tokens expire every 7 days; user must be a test user). Client id lives in `InboxButler/Support/AppConfig.swift`.
- Docs: `README.md`, `ARCHITECTURE.md` (its "not compiled yet" note and IMAP-library decision are stale; the IMAP client is custom), `docs/{SETUP_GOOGLE,TESTFLIGHT,ICLOUD}.md`.
