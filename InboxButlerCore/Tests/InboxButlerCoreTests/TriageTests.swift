import XCTest
@testable import InboxButlerCore

final class TriageTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // Wednesday 11 November 2026, 10:00 UTC
    private var wednesday: Date { date(2026, 11, 11, 10) }

    func testHiddenSnoozedAndResurfacedRules() {
        let now = wednesday
        XCTAssertFalse(TriageLogic.isHidden(nil, now: now))
        XCTAssertTrue(TriageLogic.isHidden(TriageState(isDone: true), now: now))
        let later = TriageState(remindAt: now.addingTimeInterval(3_600))
        XCTAssertTrue(TriageLogic.isHidden(later, now: now))
        XCTAssertTrue(TriageLogic.isSnoozed(later, now: now))
        XCTAssertFalse(TriageLogic.hasResurfaced(later, now: now))
        let due = TriageState(remindAt: now.addingTimeInterval(-60))
        XCTAssertFalse(TriageLogic.isHidden(due, now: now))
        XCTAssertTrue(TriageLogic.hasResurfaced(due, now: now))
        XCTAssertFalse(TriageLogic.hasResurfaced(TriageState(isDone: true, remindAt: now.addingTimeInterval(-60)), now: now))
    }

    func testReminderPresetDates() {
        let now = wednesday
        XCTAssertEqual(TriageLogic.date(for: .laterToday, from: now, calendar: cal), date(2026, 11, 11, 13))
        XCTAssertEqual(TriageLogic.date(for: .tomorrowMorning, from: now, calendar: cal), date(2026, 11, 12, 8))
        XCTAssertEqual(TriageLogic.date(for: .thisWeekend, from: now, calendar: cal), date(2026, 11, 14, 9))
        XCTAssertEqual(TriageLogic.date(for: .nextWeek, from: now, calendar: cal), date(2026, 11, 16, 8))
        // Late evening: "later today" is capped at 9pm.
        let evening = date(2026, 11, 11, 19, 30)
        XCTAssertEqual(TriageLogic.date(for: .laterToday, from: evening, calendar: cal), date(2026, 11, 11, 21))
        // Every date is in the future.
        for preset in ReminderPreset.allCases { XCTAssertGreaterThan(TriageLogic.date(for: preset, from: now, calendar: cal), now) }
    }

    func testPresetsAdaptToTheTimeAndDay() {
        let weekday = TriageLogic.availablePresets(now: wednesday, calendar: cal)
        XCTAssertEqual(weekday, ReminderPreset.allCases)
        let lateWeekday = TriageLogic.availablePresets(now: date(2026, 11, 11, 20), calendar: cal)
        XCTAssertFalse(lateWeekday.contains(.laterToday))
        let saturday = TriageLogic.availablePresets(now: date(2026, 11, 14, 10), calendar: cal)
        XCTAssertFalse(saturday.contains(.thisWeekend))
        XCTAssertTrue(saturday.contains(.nextWeek))
    }

    func testTriageStoreRoundTripAndAccountCleanup() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TriageStore(directory: dir)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        store.set(TriageState(isDone: true), for: "acc1/a")
        store.set(TriageState(remindAt: due), for: "acc2/b")
        XCTAssertEqual(store.all()["acc1/a"]?.isDone, true)
        XCTAssertEqual(store.all()["acc2/b"]?.remindAt, due)
        store.set(nil, for: "acc1/a")                       // undo
        XCTAssertNil(store.all()["acc1/a"])
        store.removeMessages(withPrefix: "acc2/")
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: Labels

    private func msg(_ subject: String, snippet: String = "", bulk: Bool = false, attachments: [AttachmentInfo] = []) -> MailMessage {
        MailMessage(accountID: UUID(), providerMessageID: "m", from: MailAddress(address: "a@b.c"), subject: subject,
                    snippet: snippet, receivedAt: Date(), attachments: attachments, isBulk: bulk)
    }

    func testLabelsForCommonMail() {
        XCTAssertEqual(MessageLabeler.labels(for: msg("Appointment confirmed Thu 14:30")).map(\.kind), [.appointment])
        XCTAssertEqual(MessageLabeler.labels(for: msg("Your verification code is 123456")).map(\.kind), [.security])
        XCTAssertEqual(MessageLabeler.labels(for: msg("Invoice 1042 - payment due Friday")).first?.kind, .invoice)
        XCTAssertEqual(MessageLabeler.labels(for: msg("Your flight itinerary")).first?.kind, .travel)
        XCTAssertEqual(MessageLabeler.labels(for: msg("Order confirmation #77")).first?.kind, .receipt)
        XCTAssertEqual(MessageLabeler.labels(for: msg("Hello", bulk: true)).map(\.kind), [.newsletter])
        XCTAssertTrue(MessageLabeler.labels(for: msg("Hi there")).isEmpty)
    }

    func testLabelsUseAttachmentsAndAreCapped() {
        let ics = AttachmentInfo(id: "1", filename: "invite.ics", mimeType: "text/calendar", byteCount: 1, kind: .calendar)
        XCTAssertTrue(MessageLabeler.labels(for: msg("See you then", attachments: [ics])).contains { $0.kind == .meeting })
        let pdf = AttachmentInfo(id: "2", filename: "doc.pdf", mimeType: "application/pdf", byteCount: 1, kind: .pdf)
        XCTAssertEqual(MessageLabeler.labels(for: msg("Contract", attachments: [pdf])).map(\.kind), [.toReview])
        let busy = msg("Invoice for your flight booking and hotel", snippet: "meeting appointment receipt")
        XCTAssertLessThanOrEqual(MessageLabeler.labels(for: busy).count, 2)
    }

    // MARK: Writer profile

    func testWriterProfileSummaryAndPrompt() {
        XCTAssertTrue(WriterProfile().isEmpty)
        let profile = WriterProfile(jobTitle: "cricket umpire", organisation: "Cricket Australia", about: "Umpires BBL and Shield matches.")
        XCTAssertEqual(profile.summary, "The user is cricket umpire at Cricket Australia. Umpires BBL and Shield matches.")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WriterProfileStore(directory: dir)
        XCTAssertNil(store.load())
        store.save(profile)
        XCTAssertEqual(store.load(), profile)

        let msg = MailMessage(accountID: UUID(), providerMessageID: "m", from: MailAddress(name: "Sam", address: "s@x.io"),
                              subject: "Match", snippet: "", receivedAt: Date())
        var style = StyleProfile()
        style.aboutUser = profile.summary
        let out = DraftPrompt.make(message: msg, body: "Can you umpire Saturday?", style: style)
        XCTAssertTrue(out.instructions.contains("Cricket Australia"))
    }
}

final class InboxClarityTests: XCTestCase {
    private func msg(_ subject: String, snippet: String = "", bulk: Bool = false) -> MailMessage {
        MailMessage(accountID: UUID(), providerMessageID: UUID().uuidString,
                    from: MailAddress(name: "Google", address: "no-reply@accounts.google.com"),
                    subject: subject, snippet: snippet, receivedAt: Date(), isBulk: bulk)
    }

    func testSecurityAlertFromNoReplyIsSecurityNotNewsletter() {
        let m = msg("Security alert for you@gmail.com", bulk: true)
        XCTAssertEqual(MessageLabeler.labels(for: m).first?.kind, .security)
        XCTAssertFalse(MessageLabeler.labels(for: m).contains { $0.kind == .newsletter })
        XCTAssertTrue(MessageLabeler.isActionable(m))
    }

    func testAccountRecoveredIsSecurity() {
        XCTAssertTrue(MessageLabeler.isActionable(msg("Your Google Account was recovered successfully", bulk: true)))
    }

    func testMarketingStaysNewsletter() {
        let m = msg("Your holiday shopping just got better", bulk: true)
        XCTAssertEqual(MessageLabeler.labels(for: m).map(\.kind), [.newsletter])
        XCTAssertFalse(MessageLabeler.isActionable(m))
    }

    func testPreviewCleaning() {
        let raw = "View in browser https://example.com/track?id=1 \u{200C}\u{200C} 3 bed, 2 bath   Study"
        XCTAssertEqual(PreviewText.clean(raw), "3 bed, 2 bath Study")
        XCTAssertEqual(PreviewText.clean("Hello there"), "Hello there")
    }

    func testGistDropsGreetingAndStopsAtSentence() {
        XCTAssertEqual(PreviewText.gist("Hi Riki, can you send the signed form by Friday? Thanks so much"),
                       "Can you send the signed form by Friday?")
        XCTAssertEqual(PreviewText.gist("short"), "Short")
        XCTAssertTrue(PreviewText.gist(String(repeating: "word ", count: 80)).hasSuffix("…"))
    }
}

final class TodayBriefTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))! }
    private func event(_ title: String, _ s: Date, _ e: Date, allDay: Bool = false) -> ExistingEvent {
        ExistingEvent(title: title, calendarTitle: "Family", start: s, end: e, isAllDay: allDay)
    }
    private func mail(_ subject: String, awaiting: Bool = false, read: Bool = false) -> MailMessage {
        MailMessage(accountID: UUID(), providerMessageID: UUID().uuidString, from: MailAddress(name: "Sam", address: "sam@x.io"),
                    subject: subject, snippet: "", receivedAt: at(8), isRead: read, awaitingReply: awaiting)
    }

    func testEventsClashesAndAllDay() {
        let events = [event("Birthday", at(0), at(23), allDay: true),
                      event("Dentist", at(15), at(16)),
                      event("School pickup", at(15, 30), at(16, 30)),
                      event("Already over", at(6), at(7))]
        let brief = TodayBrief.make(messages: [], events: events, suggestions: [], now: at(12), calendar: cal)
        XCTAssertEqual(brief.items.filter { $0.kind == .allDay }.count, 1)
        XCTAssertEqual(brief.items.filter { $0.kind == .event }.map(\.title), ["Dentist", "School pickup"])
        XCTAssertEqual(brief.items.filter { $0.kind == .clash }.count, 1)
    }

    func testMailItemsAndEmpty() {
        let sec = mail("Security alert for you@gmail.com")
        let waiting = mail("Quick question", awaiting: true)
        let brief = TodayBrief.make(messages: [sec, waiting, mail("Old alert, security alert", read: true)], events: [], suggestions: [], now: at(12), calendar: cal)
        XCTAssertEqual(brief.items.filter { $0.kind == .security }.count, 1)
        XCTAssertEqual(brief.items.first { $0.kind == .reply }?.messageID, waiting.id)
        XCTAssertTrue(TodayBrief.make(messages: [], events: [], suggestions: [], now: at(12), calendar: cal).isEmpty)
    }
}

final class BroadcastAndInlineTests: XCTestCase {
    func testRoleMailboxesAndSchoolNoticesAreBroadcast() {
        XCTAssertTrue(BulkMailDetector.isBroadcast(fromAddress: "service@paypal.co.uk", snippet: "Your statement is ready."))
        XCTAssertTrue(BulkMailDetector.isBroadcast(fromAddress: "talia@school.edu.au", snippet: "Good afternoon Year 7 students and parents, Attached is"))
        XCTAssertFalse(BulkMailDetector.isBroadcast(fromAddress: "sam@x.io", snippet: "Can you send me the form by Friday?"))
    }

    func testBroadcastNeverNeedsAReply() {
        let me = "me@x.io"
        let notice = MailMessage(accountID: UUID(), providerMessageID: "1", from: MailAddress(name: "School", address: "office@school.edu.au"),
                                 subject: "Disco", snippet: "Dear families, the disco is tomorrow.", receivedAt: Date())
        let person = MailMessage(accountID: UUID(), providerMessageID: "2", from: MailAddress(name: "Sam", address: "sam@x.io"),
                                 subject: "Quick one", snippet: "Can you call me?", receivedAt: Date())
        let status = ReplyTracker.analyze(inbox: [notice, person], sent: [], myAddresses: [me])
        XCTAssertEqual(status.awaitingMyReply, [person.id])
    }

    func testInlineImagesAreHidden() {
        let logo = AttachmentInfo(id: "a", filename: "image.png", mimeType: "image/png", byteCount: 623, kind: .image)
        let photo = AttachmentInfo(id: "b", filename: "holiday.jpg", mimeType: "image/jpeg", byteCount: 400_000, kind: .image)
        let m = MailMessage(accountID: UUID(), providerMessageID: "3", from: MailAddress(address: "a@b.c"), subject: "s",
                            snippet: "", receivedAt: Date(), attachments: [logo, photo])
        XCTAssertEqual(m.attachments.map(\.filename), ["holiday.jpg"])
    }

    func testDraftVariants() async throws {
        let m = MailMessage(accountID: UUID(), providerMessageID: "4", from: MailAddress(name: "Talia", address: "t@s.edu"),
                            subject: "Schedule", snippet: "", receivedAt: Date())
        let fyi = try await TemplateDraftService().draftReply(to: m, body: "The schedule is attached.", style: nil)
        XCTAssertTrue(fyi.body.contains("Schedule"))
        let q = try await TemplateDraftService().draftReply(to: m, body: "Can you confirm?", style: nil)
        XCTAssertTrue(q.body.contains("[add your answer here]"))
    }
}

final class ContentAwareDraftTests: XCTestCase {
    private func msg(_ subject: String) -> MailMessage {
        MailMessage(accountID: UUID(), providerMessageID: "d", from: MailAddress(name: "Talia Di Pino", address: "t@s.edu"),
                    subject: subject, snippet: "", receivedAt: Date())
    }

    func testScheduleEmailMentionsTopicAndDates() async throws {
        let body = "Good afternoon Year 7 students and parents, Attached is the year level schedule for Activities Week from Friday Week 8 to the end of Week 9."
        let d = try await TemplateDraftService().draftReply(to: msg("Year 7 - Activities Week"), body: body, style: nil)
        XCTAssertTrue(d.body.contains("Year 7 - Activities Week"))
        XCTAssertTrue(d.body.contains("Friday Week 8"))
        XCTAssertEqual(d.source, "basic")
    }

    func testRequestWithDeadline() async throws {
        let body = "Hi Sam. Please return the signed permission form by Friday. Thanks."
        let f = ContentAwareDraft.facts(subject: "Re: Excursion form", body: body, hasAttachment: false)
        XCTAssertEqual(f.topic, "Excursion form")
        XCTAssertEqual(f.deadline, "Friday")
        XCTAssertTrue(ContentAwareDraft.reply(facts: f).contains("by Friday"))
    }

    func testQuestionGetsPlaceholderNotInventedAnswer() {
        let f = ContentAwareDraft.facts(subject: "Dinner", body: "Are you free on Saturday evening for dinner?", hasAttachment: false)
        let reply = ContentAwareDraft.reply(facts: f)
        XCTAssertTrue(reply.contains("Are you free on Saturday evening for dinner"))
        XCTAssertTrue(reply.contains("[add your answer here]"))
    }
}

final class InboxSplitTests: XCTestCase {
    private func msg(from: String, labels: [String] = []) -> MailMessage {
        MailMessage(accountID: UUID(), providerMessageID: UUID().uuidString, from: MailAddress(address: from),
                    subject: "s", snippet: "", receivedAt: Date(), labels: labels.map { MailLabelTag(name: $0) })
    }

    func testMatchesByLabelAndSender() {
        let split = InboxSplit(name: "Patto", labelNames: ["Cricket - Admin"], senderPatterns: ["@patto.com", "ian@x.io"])
        XCTAssertTrue(split.matches(msg(from: "a@b.c", labels: ["cricket - admin"])))
        XCTAssertTrue(split.matches(msg(from: "bob@patto.com")))
        XCTAssertTrue(split.matches(msg(from: "IAN@x.io")))
        XCTAssertFalse(split.matches(msg(from: "bob@other.com", labels: ["unrelated"])))
        XCTAssertFalse(InboxSplit(name: "Empty").matches(msg(from: "a@b.c")))
    }

    func testLabelSuggestionsMostUsedFirst() {
        let ms = [msg(from: "a@b.c", labels: ["A", "B"]), msg(from: "a@b.c", labels: ["B"]), msg(from: "a@b.c", labels: ["C"])]
        let s = SplitSuggestions.labels(in: ms)
        XCTAssertEqual(s.map(\.name), ["B", "A", "C"])
        XCTAssertEqual(s.first?.count, 2)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = InboxSplitStore(directory: dir)
        XCTAssertTrue(store.load().isEmpty)
        let split = InboxSplit(name: "Calendar", labelNames: ["05 - calendar & appointments"])
        try store.save([split])
        XCTAssertEqual(store.load(), [split])
    }
}
