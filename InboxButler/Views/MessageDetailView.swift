import SwiftUI
import QuickLook
import InboxButlerCore

/// A message with its full text, attachments, and events found in them.
/// Everything is read and analysed on this device.
struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    let message: MailMessage

    @State private var analysis: MessageAnalysis?
    @State private var proposals: [EventProposal] = []
    @State private var isLoading = true
    @State private var htmlItem: HTMLItem?
    @State private var isLoadingHTML = false
    @State private var previewURL: URL?
    @State private var openingAttachment: String?
    @State private var alertText: String?
    @State private var confirmAddAll = false
    @State private var isAddingAll = false

    private struct HTMLItem: Identifiable { let id = UUID(); let html: String }

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
                Button {
                    Task { await showFormatted() }
                } label: {
                    if isLoadingHTML { ProgressView() } else { Label("View formatted", systemImage: "doc.richtext") }
                }
                .disabled(isLoadingHTML)
            }

            if !message.attachments.isEmpty {
                Section("Attachments") {
                    ForEach(message.attachments) { attachment in
                        Button {
                            Task { await preview(attachment) }
                        } label: {
                            HStack {
                                Label(attachment.filename, systemImage: attachment.kind.symbolName)
                                Spacer()
                                if openingAttachment == attachment.id {
                                    ProgressView()
                                } else {
                                    Text(attachment.kind == .other ? "Preview only" : byteString(attachment.byteCount))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            let visible = proposals.filter { $0.status != .dismissed }
            if !visible.isEmpty {
                Section {
                    if model.calendarAccess == .granted && !model.calendars.isEmpty {
                        Picker("Add to calendar", selection: Binding(
                            get: { model.targetCalendarID ?? "" },
                            set: { model.targetCalendarID = $0.isEmpty ? nil : $0 })) {
                            Text("Default calendar").tag("")
                            ForEach(model.calendars) { Text($0.displayName).tag($0.id) }
                        }
                    }
                    ForEach(visible, id: \.rowID) { proposal in
                        EventProposalRow(original: proposal)
                    }
                    let pending = visible.filter { $0.status == .proposed }
                    if pending.count > 1 {
                        Button {
                            confirmAddAll = true
                        } label: {
                            if isAddingAll { ProgressView() } else {
                                Label("Add all \(pending.count) to Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        .disabled(isAddingAll)
                        .confirmationDialog("Add \(pending.count) events to your calendar?",
                                            isPresented: $confirmAddAll, titleVisibility: .visible) {
                            Button("Add all \(pending.count)") { Task { await addAll() } }
                        } message: {
                            Text("They are added exactly as shown, to the calendar chosen above. Overlaps are fine. Events that already look to be in your calendar are not added twice.")
                        }
                    }
                } header: {
                    Text("Suggested events")
                } footer: {
                    Text("Found on this device in the message and its attachments. Nothing is added until you tap Add. Events that overlap others are still added: the app never blocks or skips one because of a clash.")
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
        .quickLookPreview($previewURL)
        .sheet(item: $htmlItem) { item in HTMLMessageSheet(subject: message.subject, html: item.html) }
        .alert("Message", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertText ?? "") }
        .onChange(of: previewURL) { old, new in
            // Remove the temporary copy of the attachment when the preview closes.
            if new == nil, let old { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
        }
        .onAppear { model.markReadLocally(message) }
        .task { await model.refreshCalendars() }
        .task {
            analysis = await model.analysis(for: message)
            proposals = analysis?.proposals ?? []
            isLoading = false
        }
    }

    /// Adds every pending suggestion, exactly as shown. A clash never skips an event.
    private func addAll() async {
        isAddingAll = true
        defer { isAddingAll = false }
        var added = 0, alreadyThere = 0
        for i in proposals.indices where proposals[i].status == .proposed {
            do {
                // An exact duplicate (same title and time) is already in the calendar: don't double it.
                if await model.overlap(for: proposals[i]).duplicate != nil {
                    proposals[i] = model.markDone(proposals[i], original: proposals[i])
                    alreadyThere += 1
                } else {
                    proposals[i] = try await model.addToCalendar(proposals[i], original: proposals[i])
                    added += 1
                }
            } catch {
                alertText = error.localizedDescription
                return
            }
        }
        if alreadyThere > 0 {
            alertText = "Added \(added). \(alreadyThere) already looked to be in your calendar, so they weren't added twice."
        }
    }

    private func showFormatted() async {
        isLoadingHTML = true
        defer { isLoadingHTML = false }
        do {
            if let html = try await model.htmlBody(for: message) {
                htmlItem = HTMLItem(html: html)
            } else {
                alertText = "This message has no formatted version."
            }
        } catch {
            alertText = error.localizedDescription
        }
    }

    /// Downloads the attachment to a temporary file, previews it, then deletes it.
    private func preview(_ attachment: AttachmentInfo) async {
        openingAttachment = attachment.id
        defer { openingAttachment = nil }
        do {
            let data = try await model.attachmentData(attachment, in: message)
            guard !data.isEmpty else { alertText = "No preview is available for this file."; return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = attachment.filename.replacingOccurrences(of: "/", with: "_")
            let url = dir.appendingPathComponent(name.isEmpty ? "attachment" : name)
            try data.write(to: url, options: .completeFileProtection)
            previewURL = url
        } catch {
            alertText = error.localizedDescription
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
    @State private var overlap: CalendarOverlap = .none

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
                if let dup = overlap.duplicate {
                    Label("Looks already in your calendar (\(dup.calendarTitle))", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
                if !overlap.overlaps.isEmpty {
                    Label("Overlaps: " + overlap.overlaps.map { "\($0.title) (\($0.calendarTitle))" }.joined(separator: ", "),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Text("You can still add it.").font(.caption2).foregroundStyle(.secondary)
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
            .task(id: draft.start) {
                if draft.status != .confirmed { overlap = await model.overlap(for: draft) }
            }
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

private extension EventProposal {
    /// Changes when the status changes, so a row refreshes to "Added" after Add all.
    var rowID: String { fingerprint + "-" + status.rawValue }
}
