import SwiftUI
import InboxButlerCore

/// One inbox for every account, newest first, with an optional account filter.
struct UnifiedInboxView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: UUID?   // nil = all accounts

    private var visible: [MailMessage] {
        guard let filter else { return model.messages }
        return model.messages.filter { $0.accountID == filter }
    }

    var body: some View {
        NavigationStack {
            List(visible) { message in
                NavigationLink(value: message) {
                    MessageRow(message: message, account: model.account(for: message.accountID))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Inbox")
            .navigationDestination(for: MailMessage.self) { MessageDetailView(message: $0) }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All accounts") { filter = nil }
                        ForEach(model.accounts) { account in
                            Button(account.label) { filter = account.id }
                        }
                    } label: {
                        Label("Filter", systemImage: filter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .overlay {
                if model.isRefreshing && model.messages.isEmpty { ProgressView() }
            }
        }
    }
}

private struct MessageRow: View {
    let message: MailMessage
    let account: MailAccount?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.from.display)
                        .font(.headline.weight(message.isRead ? .regular : .semibold))
                    Spacer()
                    Text(message.receivedAt, style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(message.subject)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(message.snippet)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let account { AccountBadge(account: account) }
                    if !message.attachments.isEmpty {
                        Image(systemName: "paperclip").font(.caption2).foregroundStyle(.secondary)
                    }
                    if message.awaitingReply {
                        Label("Reply waiting", systemImage: "arrowshape.turn.up.left")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
