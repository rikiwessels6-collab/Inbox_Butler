import SwiftUI
import InboxButlerCore

/// Lists connected accounts. "Add account" is a placeholder until providers are wired.
struct AccountListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddInfo = false

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
                    }
                } footer: {
                    Text("Demo data. Accounts are read-only: Inbox Butler never sends, deletes or archives mail on its own.")
                }

                Section("Add an account") {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        Button {
                            showingAddInfo = true
                        } label: {
                            Label(kind.displayName, systemImage: kind.symbolName)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .alert("Not wired up yet", isPresented: $showingAddInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Sign-in for this provider hasn't been implemented. Everything shown is demo data.")
            }
        }
    }
}
