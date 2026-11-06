import SwiftUI
import InboxButlerCore

/// A message with its full text, attachments, and events found in them.
/// Everything is read and analysed on this device.
struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    let message: MailMessage

    @State private var analysis: MessageAnalysis?
    @State private var proposals: [EventProposal] = []
    @State private var isLoading = true

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
                if model.isPriority(message) {
                    Label("Priority sender", systemImage: "star.fill").foregroundStyle(.yellow)
                } else {
                    Button {
                        model.addPrioritySender(message.from.address)
                    } label: {
                        Label("Notify me about \(message.from.display)", systemImage: "star")
                    }
                }
            }

            Section("Message") {
                if let analysis {
                    Text(String(analysis.body.prefix(4000)))
                        .textSelection(.enabled)
                } else {
                    Text(message.snippet).foregroundStyle(.secondary)
                    if isLoading { ProgressView() }
                }
            }

            if !message.attachments.isEmpty {
                Section("Attachments") {
                    ForEach(message.attachments) { attachment in
                        HStack {
                            Label(attachment.filename, systemImage: attachment.kind.symbolName)
                            Spacer()
                            Text(attachment.kind == .other ? "Not scanned" : byteString(attachment.byteCount))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let visible = proposals.filter { $0.status != .dismissed }
            if !visible.isEmpty {
                Section {
                    ForEach(visible, id: \.fingerprint) { proposal in
                        EventProposalRow(original: proposal)
                    }
                } header: {
                    Text("Suggested events")
                } footer: {
                    Text("Found on this device in the message and its attachments. Check each one: nothing is added to your calendar until you tap Add.")
                }
            } else if !isLoading {
                Section {
                    Label("No events found", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }
            }

            if let notes = analysis?.notes, !notes.isEmpty {
                Section("Couldn't scan") {
                    ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }

            Section {
                Label("A draft reply in your style will appear here. It is never sent automatically.",
                      systemImage: "square.and.pencil")
            } header: {
                Text("Coming soon")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markReadLocally(message) }
        .task {
            analysis = await model.analysis(for: message)
            proposals = analysis?.proposals ?? []
            isLoading = false
        }
    }

    private func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// One suggested event. You can fix the title and time, then Add or Dismiss.
private struct EventProposalRow: View {
    @Environment(AppModel.self) private var model
    let original: EventProposal
    @State private var draft: EventProposal
    @State private var isAdding = false
    @State private var dismissed = false
    @State private var errorText: String?

    init(original: EventProposal) {
        self.original = original
        _draft = State(initialValue: original)
    }

    var body: some View {
        if dismissed { EmptyView() } else {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $draft.title, axis: .vertical)
                    .font(.headline)
                    .disabled(draft.status == .confirmed)

                DatePicker("When", selection: startBinding,
                           displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .disabled(draft.status == .confirmed)

                if let location = draft.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse").font(.caption)
                }
                if let evidence = draft.evidence {
                    Text(evidence).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }

                if draft.status == .confirmed {
                    Label("Added to your calendar", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    HStack {
                        Button {
                            Task { await add() }
                        } label: {
                            if isAdding { ProgressView() } else { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAdding || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Dismiss", role: .cancel) {
                            model.dismiss(original)
                            dismissed = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Changing the start keeps the event's length.
    private var startBinding: Binding<Date> {
        Binding(get: { draft.start }, set: { newStart in
            if let end = draft.end { draft.end = newStart.addingTimeInterval(end.timeIntervalSince(draft.start)) }
            draft.start = newStart
        })
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        do {
            draft = try await model.addToCalendar(draft, original: original)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
