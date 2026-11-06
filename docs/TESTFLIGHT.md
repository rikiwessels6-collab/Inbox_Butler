# Getting Inbox Butler onto your iPhone/iPad with TestFlight

You do **not** need a Mac. GitHub builds the app on a Mac in the cloud and sends it to
TestFlight. You do this setup once; after that, one button makes a new build.

Everything here is done in a web browser (iPad is fine).

## 1. Apple Developer account
- Join the **Apple Developer Program** (US$99/year) at <https://developer.apple.com/programs/>.
- Find your **Team ID** (10 letters/digits): developer.apple.com > Account > **Membership details**.
  Keep it handy.

## 2. Register the app's IDs
developer.apple.com > Account > **Certificates, IDs & Profiles** > **Identifiers**.
1. **+** > **App Groups** > description `Inbox Butler`, identifier
   `group.com.boundarylineapps.InboxButler`.
2. **+** > **App IDs** > App > description `Inbox Butler`, Bundle ID **Explicit**
   `com.boundarylineapps.InboxButler`. Under Capabilities tick **App Groups**, then
   Configure and select the group above.
3. Repeat for the widget: Bundle ID `com.boundarylineapps.InboxButler.Widget`, also with
   **App Groups** and the same group.

## 3. Create the app in App Store Connect
<https://appstoreconnect.apple.com> > **Apps** > **+** > **New App**.
- Platform iOS, Name **Inbox Butler** (if taken, add something like "Inbox Butler Private"),
  Primary language, Bundle ID `com.boundarylineapps.InboxButler`, SKU anything (e.g. `inboxbutler1`).

## 4. Create an API key (lets GitHub sign and upload for you)
App Store Connect > **Users and Access** > **Integrations** > **App Store Connect API** >
**Team Keys** > **+**. Name `GitHub`, Access **Admin**. Then:
- Note the **Key ID** and the **Issuer ID** (shown at the top of the page).
- **Download** the `.p8` file. Apple only lets you download it once.

> The key is powerful. Never paste it in chat or commit it. If you ever need to, revoke it
> on the same page.

## 5. Add four secrets to GitHub
GitHub repo > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | your Team ID (step 1) |
| `ASC_KEY_ID` | the Key ID (step 4) |
| `ASC_ISSUER_ID` | the Issuer ID (step 4) |
| `ASC_KEY_P8` | open the `.p8` file as text and paste **everything**, including the `BEGIN`/`END` lines |

## 6. (For Gmail) set the Google client ID
Follow `docs/SETUP_GOOGLE.md`, then edit `InboxButler/Support/AppConfig.swift` on GitHub
(pencil icon) and commit. You can do this before or after your first TestFlight build;
builds made before it just won't be able to sign in to Gmail.

## 7. Build and send to TestFlight
GitHub > **Actions** > **TestFlight** > **Run workflow**. It takes about 10 minutes. A red
cross means a problem: open the run and read the "errors" section, then tell me what it says.

## 8. Install it
1. App Store Connect > your app > **TestFlight**. The build shows "Processing" for 5 to 20
   minutes. Wait for it to finish.
2. **Internal Testing** > **+** > create a group, add yourself (you must be a user on the
   account, which you are as the owner).
3. Install the **TestFlight** app from the App Store on your iPhone/iPad, sign in with the
   same Apple ID, and tap **Install** on Inbox Butler.

Each new run of the workflow makes a new build with a higher number, which appears in
TestFlight automatically.

## Notes
- Private repos use GitHub's free build minutes. Mac builds count 10x, so a free account
  (2,000 minutes/month) allows roughly 40 builds a month. Fine for testing.
- The app icon is a placeholder (a white envelope on blue). Replace
  `InboxButler/Assets.xcassets/AppIcon.appiconset/icon.png` with your own 1024x1024 PNG
  (no transparency) any time.
- The widget and notifications work from the first build. Widget: long-press the Home Screen
  > **+** > Inbox Butler.
