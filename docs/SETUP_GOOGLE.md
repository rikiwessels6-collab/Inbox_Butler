# Connecting Gmail: one-time Google setup

You do this once, in a web browser, on any computer or iPad. It is free. Google
shows an "unverified app" warning because this is your own private app; that is
expected.

You will end up with a **Client ID** (a long text ending in
`.apps.googleusercontent.com`) that you paste into the app. It is not a secret.

## 1. Create a project
1. Go to <https://console.cloud.google.com> and sign in with your Google account.
2. Top bar, project picker > **New project**. Name it `Inbox Butler` > **Create**.
3. Make sure that project is selected in the top bar.

## 2. Turn on the Gmail API
1. Menu > **APIs & Services** > **Library**.
2. Search **Gmail API** > open it > **Enable**.

## 3. Set up the consent screen
Google's console labels vary a little over time ("OAuth consent screen" or
"Google Auth Platform"). Follow the same ideas:
1. **App name:** Inbox Butler. **Support email:** your email.
2. **Audience / User type:** **External**. Contact email: your email.
3. **Data access / Scopes:** add exactly one scope:
   `https://www.googleapis.com/auth/gmail.readonly` (read-only Gmail).
   Do **not** add any other Gmail scope.
4. **Test users:** add every Gmail address you want to connect.

## 4. Create the iOS sign-in key
1. **Credentials** (or **Clients**) > **Create credentials / Create client** >
   **OAuth client ID**.
2. Application type: **iOS**.
3. Bundle ID: `com.boundarylineapps.InboxButler`  (must match exactly).
4. Create. Copy the **Client ID**.

## 5. Put the Client ID in the app
Open `InboxButler/Support/AppConfig.swift` and replace
`YOUR_IOS_CLIENT_ID.apps.googleusercontent.com` with your Client ID.

## 6. Stop the weekly sign-out (do this before regular use)
While the consent screen's status is **Testing**, Google logs you out every
**7 days**. To stop that:
1. Consent screen / **Audience** page > **Publish app** > confirm, so the status
   becomes **In production**.
2. Do **not** click "submit for verification". Verification is only needed for a
   public release.
3. Effects: a one-time "Google hasn't verified this app" warning, and a
   100-user limit. Both are fine for private use.

Google changes these screens and rules from time to time. If a step looks
different, tell me what you see.

## 7. First sign-in
Accounts tab > **Gmail**. On the warning page choose **Advanced** > **Go to
Inbox Butler (unsafe)** > allow the read-only access.

## Good to know
- The app asks for **read-only** access. It cannot send, delete or change mail.
- Remove an account in the app (swipe it) and the app also revokes its access at
  Google. You can check or revoke anytime at <https://myaccount.google.com/permissions>.
- Only a revoked grant, a password change, or ~6 months of not using the app
  will sign you out once you are In production.
