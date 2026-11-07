# Connecting iCloud Mail

iCloud only lets third-party apps in with an **app-specific password**, a one-off code that
works for mail only. Your real Apple ID password is never used or stored.

1. On your iPad or iPhone, open Safari and go to **appleid.apple.com**. Sign in.
2. **Sign-In and Security** > **App-Specific Passwords**.
3. Tap **+** (Generate), name it `Inbox Butler`, and tap Create. You may be asked for your
   Apple ID password and a code.
4. Copy the password shown (it looks like `abcd-efgh-ijkl-mnop`). Apple shows it once.
5. In Inbox Butler: **Accounts** > **iCloud Mail**. Enter your iCloud email address and paste the
   app-specific password. Tap **Connect**.

Notes
- Your iCloud account needs two-factor authentication on (it normally is).
- Inbox Butler only reads. It never sends, deletes, moves or flags mail, and the password is
  stored in the iOS Keychain on this device.
- iCloud mail has no conversation threads, so "needs a reply" and "waiting on others" group a
  conversation by its subject line (ignoring Re:/Fwd:).
- To disconnect: in the app swipe/tap the account's menu > Remove. You can also delete the
  app-specific password at appleid.apple.com at any time.
