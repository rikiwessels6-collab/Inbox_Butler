import SwiftUI
import InboxButlerCore

enum InboxFilter: Hashable {
    case all, priority, needsReply, newsletters, waiting
    case account(UUID)
}

/// Three columns on iPad (filters, mail list, message) that collapse to a normal
/// stack on iPhone. Search covers every account and works offline.
struct UnifiedInboxView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: InboxFilter? = .all
    @State private var selectedID: String?
    @State private var search = ""
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @State private var compactColumn: NavigationSplitViewColumn = .content   // iPhone opens on the list

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar
        } content: {
            list
        } detail: {
            detail
        }
    }

    // MARK: Columns

    private var sidebar: some View {
        List(selection: $filter) {
            Section("Inbox") {
                row("All mail", "tray.full", .all, model.messages.filter { !$0.isRead }.count)
                row("Priority", "star.fill", .priority, model.messages.filter { !$0.isRead && isImportant($0) }.count)
                row("Needs a reply", "arrowshape.turn.up.left", .needsReply, model.messages.filter(\.awaitingReply).count)
                row("Waiting on others", "clock", .waiting, model.waitingOnOthers.count)
                row("Newsletters", "newspaper", .newsletters, model.messages.filter { !$0.isRead && $0.isBulk }.count)
            }
            Section("Accounts") {
                ForEach(model.accounts) { account in
                    Label(account.label, systemImage: account.kind.symbolName)
                        .foregroundStyle(account.badgeColor)
                        .tag(InboxFilter.account(account.id))
                }
            }
        }
        .navigationTitle("Inbox Butler")
    }

    private func row(_ title: String, _ icon: String, _ value: InboxFilter, _ count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
        }
        .tag(value)
    }

    private var list: some View {
        List(items, selection: $selectedID) { message in
            MessageRow(message: message,
                       account: model.account(for: message.accountID),
                       isPriority: model.isPriority(message),
                       showRecipient: filter == .waiting)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Search all mail")
        .refreshable { await model.refresh() }
        .overlay {
            if model.isRefreshing && model.messages.isEmpty { ProgressView() }
            else if items.isEmpty && !model.isRefreshing {
                ContentUnavailableView(search.isEmpty ? "Nothing here" : "No results",
                                       systemImage: search.isEmpty ? "tray" : "magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let message = (model.messages + model.waitingOnOthers).first(where: { $0.id == id }) {
            MessageDetailView(message: message).id(message.id)   // fresh state per message
        } else {
            ContentUnavailableView("Select a message", systemImage: "envelope.open")
        }
    }

    // MARK: Data

    private func isImportant(_ m: MailMessage) -> Bool {
        !m.isBulk && (model.isPriority(m) || (m.importance ?? 0) >= 0.7)
    }

    private var title: String {
        switch filter ?? .all {
        case .all: return "All mail"
        case .priority: return "Priority"
        case .needsReply: return "Needs a reply"
        case .newsletters: return "Newsletters"
        case .waiting: return "Waiting on others"
        case .account(let id): return model.account(for: id)?.label ?? "Account"
        }
    }

    private var items: [MailMessage] {
        let base: [MailMessage]
        switch filter ?? .all {
        case .all: base = model.messages
        case .priority: base = model.messages.filter(isImportant)
        case .needsReply: base = model.messages.filter(\.awaitingReply)
        case .newsletters: base = model.messages.filter(\.isBulk)
        case .waiting: base = model.waitingOnOthers
        case .account(let id): base = model.messages.filter { $0.accountID == id }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { m in
            [m.subject, m.snippet, m.from.display, m.from.address].contains { $0.lowercased().contains(q) }
        }
    }
}

private struct MessageRow: View {
    let message: MailMessage
    let account: MailAccount?
    let isPriority: Bool
    let showRecipient: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.isRead || showRecipient ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if isPriority {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                            .accessibilityLabel("Priority sender")
                    }
                    Text(showRecipient ? "To \(message.to.first?.display ?? "")" : message.from.display)
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
                            .accessibilityLabel("Has attachments")
                    }
                    if message.awaitingReply {
                        Label("Reply waiting", systemImage: "arrowshape.turn.up.left")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if message.isBulk {
                        Label("Newsletter", systemImage: "newspaper").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
