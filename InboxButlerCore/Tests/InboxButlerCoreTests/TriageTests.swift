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
