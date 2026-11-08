# Inbox Butler — Superhuman-inspired product redesign

Status: Phase 1 design and implementation plan. Branch: feature/superhuman-inspired-redesign.

## Product direction
Create a premium, fast, keyboard-friendly, privacy-conscious email assistant with a cinematic mountain welcome screen and a distinctive butler-and-envelope mark. Inspiration: Superhuman's emphasis on rapid triage, clear priorities, minimal distractions, shortcuts and polished interactions. Do not copy its assets, trade dress or proprietary UI.

## Existing SwiftUI architecture to preserve
- AppRouter and RootView tab routing, onboarding and optional Face ID lock.
- UnifiedInboxView filters: All, Important, Other, Needs Reply, Drafts, Waiting, Newsletters, Reminders, Done and account-specific mail.
- NavigationSplitView on iPad, compact navigation on iPhone.
- Search, message detail, reminder sheet, swipe actions, undo toast, offline behaviour and refresh.
- Existing account providers, permissions and on-device privacy model. Do not claim send/AI capabilities until verified working.

## Screen map and delivery order
1. Welcome: cinematic image, editable butler identity, dynamic legibility overlay, provider-aware connection choices, accessible fallback.
2. Today: briefing composed from existing model counts, follow-ups and calendar data; deep links into real filters; no invented AI content.
3. Inbox: compact list rows, persistent split inbox filters, clear unread/priority/reply state, fast triage and undo.
4. Message detail: reading-first typography, accessible action toolbar, attachments, reply workflows according to supported permissions.
5. Calendar and Search: fast global search, filters, calendar context.
6. Settings/Accounts: provider connection status, privacy, notification controls, theme and shortcuts.
7. AI assistant: clearly labelled as unavailable until the actual model-backed workflow is implemented and tested.

## Design foundation
- Welcome: cinematic landscape sunrise, butler holding envelope on tray, white typography, restrained teal highlights.
- Inside app: ink #090D1B, surface #171D32, elevated #202840, foreground #F7F8FF, secondary #A0ABC5, teal #65E2DC, violet #9477FF.
- Gradients should be atmospheric accents, not reduce email legibility.
- Dynamic Type, VoiceOver labels, sufficient contrast, reduced-motion support, 44pt touch targets, dark and light modes.
- iPhone and iPad layouts, including compact and split view.
- Keep images, colours and typography replaceable through SwiftUI assets/tokens.

## Behavioural parity goals (not claims of current implementation)
- Split inboxes and priority triage.
- Swipe and shortcut-driven archive/done/remind actions with undo.
- Rapid search and account switching.
- Follow-up and waiting-on-others visibility.
- Fast reading, keyboard navigation and focused compose where sending is supported.
- Calendar integration and contextual suggestions only where source data and permissions allow.
- AI summaries and drafting only after real feature implementation, opt-in and privacy review.

## Engineering approach
- Incremental, reversible SwiftUI changes on this branch; no provider/authentication or storage migrations for a visual redesign.
- Introduce a design system and screen components before replacing RootView navigation.
- Retain existing AppTab routing until equivalent destinations are implemented; don't create dead tabs.
- Gate experimental Today/Assistant destinations behind explicit feature flags if needed.
- Use anonymised fixture mail for UI previews, screenshots and tests.
- Add regression coverage for triage, undo, filter counts, navigation, lock overlays, offline search, account switching and Dynamic Type.
- Verify supported providers and mail send permissions before adding any sign-in or compose CTA.
- Build, test and distribute to TestFlight only after the user reviews the new UI and approves the release.

## Figma
Design file: https://www.figma.com/design/yUTv8vKt1XsaDyduW77qwf
Existing: cinematic Welcome, Today and Inbox mockups. These are design artefacts, not live iOS functionality.

## Acceptance criteria for first implementation milestone
- Welcome view visually matches approved Figma direction without blocking existing onboarding.
- Today renders only real AppModel data and navigates to existing inbox filters.
- Inbox displays all existing filters and supports the same swipe/undo and message detail flows.
- No regression to account access, privacy, Face ID, iPad split view, search or accessibility.
- No unimplemented provider or AI capabilities shown as functioning.
