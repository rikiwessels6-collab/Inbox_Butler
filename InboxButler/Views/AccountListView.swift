import SwiftUI
import InboxButlerCore

/// Connected accounts and the ways to add more.
struct AccountListView: View {
    @Environment(AppModel.self) private var model
    @State private var isSigningIn = false
    @State private var message: String?
    @State private var pendingRemoval: MailAccount?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accounts").font(.serif(.largeTitle)).foregroundStyle(Theme.ink)
                        Text("Read-only. Inbox Butler never sends, deletes or archives mail on its own.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }

                    connectedSection
                    addSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .alert("Accounts", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .confirmationDialog("Remove \(pendingRemoval?.emailAddress ?? "account")?",
                                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible) {
                Button("Remove and revoke access", role: .destructive) {
                    if let account = pendingRemoval { Task { await model.removeAccount(account) } }
                }
            } message: {
                Text("Deletes the saved sign-in and the cached mail on this device, and tells Google to revoke access. Your mailbox itself is not touched.")
            }
        }
    }

    // MARK: Connected

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: model.usingDemoData ? "Demo accounts (not real)" : "Connected")
            VStack(spacing: 0) {
                ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                    HStack(spacing: 14) {
                        tile(account.kind.symbolName, tint: account.badgeColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.emailAddress).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                            if let error = model.errors[account.id] {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(Theme.warn).lineLimit(2)
                            } else {
                                Text(model.usingDemoData ? "Demo data" : account.kind.displayName)
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        if !model.usingDemoData {
                            Menu {
                                Button("Remove account", role: .destructive) { pendingRemoval = account }
                            } label: {
                                Image(systemName: "ellipsis").foregroundStyle(Theme.muted).padding(8)
                            }
                        }
                    }
                    .padding(14)
                    if index < model.accounts.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 70) }
                }
            }
            .card(padding: 0)
            if model.usingDemoData {
                Text("Showing demo accounts and fake mail until you connect a real account below.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Add an account")
            VStack(spacing: 0) {
                providerRow(.gmail, title: "Google", subtitle: "Gmail, read-only", busy: isSigningIn) {
                    Task { await addGmail() }
                }
                Divider().overlay(Theme.hairline).padding(.leading, 70)
                providerRow(.icloud, title: "iCloud Mail", subtitle: "Needs an app-specific password", soon: true) {
                    message = "iCloud Mail is the next thing being built."
                }
                Divider().overlay(Theme.hairline).padding(.leading, 70)
                providerRow(.microsoft, title: "Outlook / Hotmail", subtitle: "Microsoft account", soon: true) {
                    message = "Outlook isn't available yet."
                }
                Divider().overlay(Theme.hairline).padding(.leading, 70)
                providerRow(.imap, title: "Other (IMAP)", subtitle: "Any mail server", soon: true) {
                    message = "Other IMAP accounts aren't available yet."
                }
            }
            .card(padding: 0)
        }
    }

    private func providerRow(_ kind: AccountKind, title: String, subtitle: String, busy: Bool = false,
                             soon: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                tile(kind.symbolName, tint: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if busy { ProgressView() }
                else if soon { PillLabel(text: "Soon") }
                else { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent) }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func tile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addGmail() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await model.addGmailAccount()
        } catch let error as SignInError {
            if case .failed(let text) = error { message = text }   // cancelled = silent
        } catch {
            message = error.localizedDescription
        }
    }
}
