import SwiftUI
import QuickLook
import InboxButlerCore

/// A message laid out for reading, with its attachments and the events found in them.
/// Everything is read and analysed on this device.
struct MessageDetailView: View {
    @Environment(AppModel.self) private var model
    let message: MailMessage
    /// Called after Done / Remind so the list can close this message.
    var onTriage: (() -> Void)? = nil

    @State private var showReminder = false
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
    @State private var replyText = ""
    @State private var showComposer = false
    @State private var showNoMailAlert = false

    private struct HTMLItem: Identifiable { let id = UUID(); let html: String }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                messageBody
                if !model.isFromMe(message) { replySection }
                if !message.attachments.isEmpty { attachmentsSection }
                eventsSection
                notesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showReminder = true } label: { Image(systemName: "clock") }
                    .accessibilityLabel("Remind me")
                Button { model.markDone(message); onTriage?() } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Mark done")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await showFormatted() } } label: {
                        Label("View formatted", systemImage: "doc.richtext")
                    }
                    if !model.isPriority(message) {
                        Button { model.addPrioritySender(message.from.address) } label: {
                            Label("Notify me about \(message.from.display)", systemImage: "star")
                        }
                    }
                } label: {
                    if isLoadingHTML { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showReminder) {
            ReminderSheet(message: message) { date in model.remind(message, at: date); onTriage?() }
        }
        .sheet(isPresented: $showComposer) {
            MailComposer(to: [message.from.address],
                         subject: ReplyFormatter.subject(message.subject),
                         body: replyText + "\n\n" + ReplyFormatter.quoted(original: analysis?.body ?? message.snippet,
                                                                          sender: message.from.display, date: message.receivedAt),
                         preferredFrom: model.account(for: message.accountID)?.emailAddress) { result in
                showComposer = false
                if result == .sent { model.discardDraft(for: message); replyText = "" }
            }
            .ignoresSafeArea()
        }
        .alert("Mail isn't set up on this device", isPresented: $showNoMailAlert) {
            Button("Copy reply") { UIPasteboard.general.string = replyText }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add this email account in the iOS Mail app (Settings > Apps > Mail > Mail Accounts) to send from here. You can copy your reply and paste it into your mail app now.")
        }
        .task(id: model.draft(for: message)?.id) { replyText = model.draft(for: message)?.body ?? "" }
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

    // MARK: Header and body

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message.subject)
                .font(.serif(.title))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Avatar(name: message.from.display, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.from.display).font(.headline).foregroundStyle(Theme.ink)
                    Text(message.from.address).font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 8) {
                if let account = model.account(for: message.accountID) { AccountBadge(account: account) }
                if model.isPriority(message) { PillLabel(text: "Priority", systemImage: "star.fill", tint: Theme.gold) }
                if message.awaitingReply { PillLabel(text: "Needs reply", systemImage: "arrowshape.turn.up.left", tint: Theme.warn) }
                ForEach(MessageLabeler.labels(for: message, body: analysis?.body, max: 3)) { label in
                    PillLabel(text: label.title, systemImage: label.symbolName, tint: label.tint)
                }
            }
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        Divider().overlay(Theme.hairline)
        if let analysis {
            if analysis.isPartial { partialBanner }
            Text(String(analysis.body.prefix(4000)))
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.snippet).font(.body).foregroundStyle(Theme.muted)
                if isLoading { ProgressView() }
            }
        }
    }

    /// Shown when only the short preview loaded, instead of silently pretending it is the whole email.
    private var partialBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Only a short preview loaded").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("Open the full email to read all of it.").font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button("Open") { Task { await showFormatted() } }
                .buttonStyle(SecondaryButtonStyle())
        }
        .card(padding: 12)
    }

    // MARK: Reply

    private var replySection: some View {
        let drafting = model.isDraftingIDs.contains(message.id)
        let draft = model.draft(for: message)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Reply")
                Spacer()
                if let draft {
                    PillLabel(text: draft.source == "on-device" ? "Written on this device" : "Quick draft",
                              systemImage: draft.source == "on-device" ? "sparkles" : "text.alignleft",
                              tint: draft.source == "on-device" ? Theme.accent : Theme.muted)
                }
            }
            if let draft, draft.source != "on-device" {
                Text((DraftAI.unavailableReason ?? "The on-device model couldn't write this one.") + " This quick draft is built from what the email says, so check it and fill in anything in [brackets].")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            if drafting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing a draft in your style…").font(.subheadline).foregroundStyle(Theme.muted)
                }
            } else if draft != nil {
                TextEditor(text: $replyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(10)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: replyText) { _, new in model.saveDraftText(new, for: message) }
                HStack(spacing: 10) {
                    Button {
                        if MailComposer.canSend { showComposer = true } else { showNoMailAlert = true }
                    } label: {
                        Label("Review & send", systemImage: "paperplane")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Regenerate") {
                        Task { await startDraft(replacing: true) }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()
                    Button("Discard", role: .destructive) {
                        model.discardDraft(for: message)
                        replyText = ""
                    }
                    .font(.subheadline)
                }
                Text("Edit the draft above. \"Review & send\" opens the mail sheet with it filled in: nothing is sent until you tap Send there.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                Button {
                    Task { await startDraft(replacing: false) }
                } label: {
                    Label("Draft a reply", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Written on this device in your style. Never sent automatically.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    private func startDraft(replacing: Bool) async {
        if replacing { model.discardDraft(for: message) }
        await model.generateDraft(for: message, body: analysis?.body)
        replyText = model.draft(for: message)?.body ?? ""
    }

    // MARK: Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Attachments")
            VStack(spacing: 0) {
                ForEach(Array(message.attachments.enumerated()), id: \.element.id) { index, attachment in
                    Button { Task { await preview(attachment) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attachment.kind.symbolName)
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.filename).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(attachment.kind == .other ? "Preview only" : byteString(attachment.byteCount))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if openingAttachment == attachment.id {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < message.attachments.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 66) }
                }
            }
            .card(padding: 0)
        }
    }

    // MARK: Events

    @ViewBuilder
    private var eventsSection: some View {
        let visible = proposals.filter { $0.status != .dismissed }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Suggested events")
                if model.calendarAccess == .granted && !model.calendars.isEmpty { calendarPicker }
                ForEach(visible, id: \.rowID) { proposal in
                    EventProposalRow(original: proposal)
                }
                let pending = visible.filter { $0.status == .proposed }
                if pending.count > 1 {
                    Button { confirmAddAll = true } label: {
                        if isAddingAll { ProgressView() } else {
                            Label("Add all \(pending.count) to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isAddingAll)
                    .confirmationDialog("Add \(pending.count) events to your calendar?",
                                        isPresented: $confirmAddAll, titleVisibility: .visible) {
                        Button("Add all \(pending.count)") { Task { await addAll() } }
                    } message: {
                        Text("They are added exactly as shown, to the calendar chosen above. Overlaps are fine. Events that already look to be in your calendar are not added twice.")
                    }
                }
                Text("Found on this device in the message and its attachments. Nothing is added until you tap Add. Events that overlap others are still added: the app never blocks or skips one because of a clash.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        } else if !isLoading {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(Theme.muted)
                Text("No events found in this message").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    private var calendarPicker: some View {
        Menu {
            Button { model.targetCalendarID = nil } label: {
                if model.targetCalendarID == nil { Label("Default calendar", systemImage: "checkmark") } else { Text("Default calendar") }
            }
            ForEach(model.calendars) { calendar in
                Button { model.targetCalendarID = calendar.id } label: {
                    if model.targetCalendarID == calendar.id { Label(calendar.displayName, systemImage: "checkmark") }
                    else { Text(calendar.displayName) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add to").font(.caption).foregroundStyle(Theme.muted)
                    Text(model.calendars.first { $0.id == model.targetCalendarID }?.displayName ?? "Default calendar")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.muted)
            }
            .card(padding: 14)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let notes = analysis?.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Couldn't scan")
                ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.muted) }
            }
        }
    }

    // MARK: Actions

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

// MARK: - One suggested event

/// A suggested event. You can fix the title and time, then Add or Dismiss.
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

    private var added: Bool { draft.status == .confirmed }

    private var timeText: String {
        if draft.isAllDay { return "All day" }
        let start = draft.start.formatted(date: .omitted, time: .shortened)
        guard let end = draft.end else { return start }
        return start + " – " + end.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        if dismissed { EmptyView() } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Text(draft.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        Text(draft.start.formatted(.dateTime.day()))
                            .font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    }
                    .frame(width: 54, height: 54)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Title", text: $draft.title, axis: .vertical)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .disabled(added)
                        Text(timeText).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }

                DatePicker("When", selection: startBinding,
                           displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .font(.subheadline)
                    .disabled(added)

                if let location = draft.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(Theme.muted)
                }
                if let evidence = draft.evidence {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.hairline).frame(width: 3)
                        Text(evidence).font(.footnote).foregroundStyle(Theme.muted).lineLimit(3)
                    }
                }

                if let dup = overlap.duplicate {
                    PillLabel(text: "Looks already in your calendar (\(dup.calendarTitle))",
                              systemImage: "checkmark.circle", tint: Theme.good)
                }
                if !overlap.overlaps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        PillLabel(text: "Overlaps: " + overlap.overlaps.map { "\($0.title) (\($0.calendarTitle))" }.joined(separator: ", "),
                                  systemImage: "exclamationmark.triangle", tint: Theme.warn)
                        Text("You can still add it.").font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }

                if added {
                    Label("Added to your calendar", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.good)
                } else {
                    HStack(spacing: 10) {
                        Button { Task { await add() } } label: {
                            if isAdding { ProgressView().tint(.white) } else {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isAdding || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Dismiss") {
                            model.dismiss(original)
                            withAnimation(.snappy) { dismissed = true }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .card()
            .sensoryFeedback(.success, trigger: added)
            .task(id: draft.start) {
                if !added { overlap = await model.overlap(for: draft) }
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
