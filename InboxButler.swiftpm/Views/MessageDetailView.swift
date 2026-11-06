import SwiftUI
import InboxButlerCore

/// Message detail. Attachments / events / drafts sections are placeholders for
/// the upcoming modules.
struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    let message: MailMessage

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.subject).font(.title3.weight(.semibold))
                    Text("From \(message.from.display)").font(.subheadline)
                    if let account = model.account(for: message.accountID) {
                        AccountBadge(account: account)
                    }
                }
                Text(message.snippet)
            }

            if !message.attachments.isEmpty {
                Section("Attachments") {
                    ForEach(message.attachments) { a in
                        Label("\(a.filename) (\(a.byteCount / 1000) KB)", systemImage: "doc")
                    }
                }
            }

            Section {
                Label("Suggested events appear here. Nothing is added to your calendar until you confirm.",
                      systemImage: "calendar.badge.plus")
                Label("A draft reply in your style appears here. It is never sent automatically.",
                      systemImage: "square.and.pencil")
            } header: {
                Text("Coming soon")
            } footer: {
                Text("AI features need a choice between on-device and a backend proxy. See ARCHITECTURE.md.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markReadLocally(message) }
    }
}
