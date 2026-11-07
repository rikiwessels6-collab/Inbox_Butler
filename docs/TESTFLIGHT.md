# Getting Inbox Butler onto your iPhone/iPad (the easy way)

No Mac needed. GitHub builds the app in the cloud and sends it to TestFlight. Everything
below is done in Safari on your iPad. The first build **skips the widget** so you avoid
the hardest Apple setup; you can add the widget later (Part B).

## Part A: first build (about 6 steps)

### 1. Register the app's name with Apple (one screen)
developer.apple.com > Account > Certificates, Identifiers & Profiles > Identifiers > **+**
> **App IDs** > Continue > **App** > Continue.
- Description: `Inbox Butler`
- Bundle ID: **Explicit**, `com.boundarylineapps.InboxButler`
- Don't tick any capabilities. Continue > Register.

(If you already registered it, with or without capabilities ticked, that's fine. Leave it.)

### 2. Create the app in App Store Connect
appstoreconnect.apple.com > Apps > **+** > New App.
- Platform iOS, Name `Inbox Butler` (add a word if it's taken), language English (Australia).
- Bundle ID: choose `com.boundarylineapps.InboxButler` from the list.
- SKU: `inboxbutler1`. User Access: Full Access. Create.

### 3. Make an API key (lets GitHub sign and upload for you)
App Store Connect > **Users and Access** > **Integrations** > **App Store Connect API** >
**Team Keys** > **+**. Name `GitHub`, Access **Admin**, Generate.
- Write down the **Key ID** and the **Issuer ID** (top of the page).
- Tap **Download** to save the `.p8` file (Apple only lets you do this once).

> Never paste the key into chat. It only goes into GitHub (step 4).

### 4. Add four secrets in GitHub
Your repo > **Settings** > **Secrets and variables** > **Actions** > **New repository secret**.

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com > Account > Membership details > Team ID |
| `ASC_KEY_ID` | the Key ID from step 3 |
| `ASC_ISSUER_ID` | the Issuer ID from step 3 |
| `ASC_KEY_P8` | open the `.p8` file as text and paste **everything**, including the BEGIN and END lines |

### 5. Build and send
GitHub > **Actions** > **TestFlight** > **Run workflow** (leave "Include the widget" **off**)
> Run. It takes about 10 minutes. If it turns red, open it and send me the "errors" section.

### 6. Install it
App Store Connect > your app > **TestFlight**. Wait for "Processing" to finish (5 to 20
minutes), then **Internal Testing** > **+** > create a group and add yourself. Install the
**TestFlight** app from the App Store, sign in with the same Apple ID, and tap **Install**.

Each new run makes a new build with a higher number.

## Part B: add the widget and Time Sensitive alerts (later, optional)
1. Identifiers > **+** > **App Groups** > `group.com.boundarylineapps.InboxButler`.
2. Open the app's ID, tick **App Groups** (then **Configure** and tick the group) and
   **Time Sensitive Notifications**. Save.
3. Register a second App ID `com.boundarylineapps.InboxButler.Widget` with **App Groups**
   (same group).
4. Run the TestFlight workflow again with **Include the widget** switched **on**.
5. On your device: long-press the Home Screen > **+** > Inbox Butler. Open the app once first.

## Notes
- Private repos use GitHub's free build minutes (Mac builds count 10x, so roughly 40 builds a
  month on a free account).
- The app icon is a placeholder; replace
  `InboxButler/Assets.xcassets/AppIcon.appiconset/icon.png` with your own 1024x1024 PNG.
- Without the widget build, the app works the same; Siri's "what's urgent" and the widget
  need the Part B setup to show data.
