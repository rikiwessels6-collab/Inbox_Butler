import SwiftUI
import InboxButlerCore

/// Connected accounts, plus "Add an account". Gmail is wired up; the others
/// arrive in later steps.
struct AccountListView: View {
    @Environment(AppModel.self) private var model
    @State private var isSigningIn = false
    @State private var message: String?
    @State private var pendingRemoval: MailAccount?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 12) {
                            Image(systemName: account.kind.symbolName)
                                .foregroundStyle(account.badgeColor)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(account.emailAddress)
                                Text(account.kind.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let error = model.errors[account.id] {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Sync problem: \(error)")
                            }
                        }
                        .swipeActions {
                            if !model.usingDemoData {
                                Button("Remove", role: .destructive) { pendingRemoval = account }
                            }
                        }
                    }
                } header: {
                    if model.usingDemoData { Text("Demo accounts (not real)") }
                } footer: {
                    Text(model.usingDemoData
                         ? "Showing fake demo mail until you connect a real account."
                         : "Read-only: Inbox Butler never sends, deletes or archives mail on its own. Swipe an account to remove it.")
                }

                Section("Add an account") {
                    Button {
                        Task { await addGmail() }
                    } label: {
                        HStack {
                            Label("Gmail", systemImage: AccountKind.gmail.symbolName)
                            if isSigningIn { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isSigningIn)

                    ForEach([AccountKind.microsoft, .icloud, .imap], id: \.self) { kind in
                        Button {
                            message = "\(kind.displayName) isn't available yet. Gmail comes first."
                        } label: {
                            Label(kind.displayName, systemImage: kind.symbolName)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
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
