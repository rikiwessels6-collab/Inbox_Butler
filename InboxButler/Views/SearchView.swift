import SwiftUI
import InboxButlerCore

/// Search across every account at once. Works offline, on the mail already on this device.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var scope: Scope = .all
    @AppStorage("recentSearches") private var recentRaw = ""

    enum Scope: String, CaseIterable, Identifiable {
        case all = "Everything", important = "Important", attachments = "Attachments", needsReply = "Needs reply", done = "Done"
        var id: String { rawValue }
    }

    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var results: [MailMessage] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty || scope != .all else { return [] }
        let pool: [MailMessage]
        switch scope {
        case .all: pool = model.messages
        case .important: pool = model.messages.filter { !$0.isBulk && model.isPriority($0) }
        case .attachments: pool = model.messages.filter { !$0.attachments.isEmpty }
        case .needsReply: pool = model.messages.filter(\.awaitingReply)
        case .done: pool = model.doneMessages
        }
        return pool.filter { m in
            let haystack = [m.subject, m.snippet, m.from.display, m.from.address,
                            m.attachments.map(\.filename).joined(separator: " ")].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
        .sorted { $0.receivedAt > $1.receivedAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Search").font(.serif(.largeTitle)).foregroundStyle(Theme.ink)
                    searchField
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Scope.allCases) { s in
                                FilterChip(title: s.rawValue, selected: scope == s) { withAnimation(.snappy) { scope = s } }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)

                if query.isEmpty && scope == .all { idleState } else { resultList }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MailMessage.self) { MessageDetailView(message: $0) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search mail, people, attachments", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { remember(query) }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
    }

    private var resultList: some View {
        List(results) { message in
            NavigationLink(value: message) {
                MessageRow(message: message, account: model.account(for: message.accountID),
                           isPriority: model.isPriority(message), showRecipient: false)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparatorTint(Theme.hairline)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try a different word, or another filter."))
            }
        }
    }

    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "Recent")
                            Spacer()
                            Button("Clear") { recentRaw = "" }.font(.footnote)
                        }
                        VStack(spacing: 0) {
                            ForEach(recents, id: \.self) { term in
                                Button { query = term } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.muted)
                                        Text(term).foregroundStyle(Theme.ink)
                                        Spacer()
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                                if term != recents.last { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                            }
                        }
                        .card(padding: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Try")
                    Text("Search by sender, subject, a word in the preview, or an attachment's file name. Use the filters above to narrow it down.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
        }
    }

    private func remember(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        recentRaw = list.prefix(6).joined(separator: "\n")
    }
}
