import XCTest
@testable import InboxButlerCore

final class AttachmentTests: XCTestCase {
    private let ref = Date()

    private func utcStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    // MARK: ICS

    func testICSParsesTimedEventWithFoldingAndEscapes() {
        let start = ref.addingTimeInterval(2 * 86_400)
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:1\r
        SUMMARY:Team lunch\\, with cake\r
        DTSTART:\(utcStamp(start))\r
        DTEND:\(utcStamp(start.addingTimeInterval(5400)))\r
        LOCATION:The Pub\r
        DESCRIPTION:Bring\r
         \u{20}your appetite\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let events = ICSParser.events(from: ics, sourceMessageID: "m", referenceDate: ref, filename: "invite.ics")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].title, "Team lunch, with cake")
        XCTAssertEqual(events[0].location, "The Pub")
        XCTAssertEqual(events[0].notes, "Bring your appetite")
        XCTAssertEqual(events[0].end?.timeIntervalSince(events[0].start), 5400)
        XCTAssertFalse(events[0].isAllDay)
        XCTAssertEqual(events[0].source, .calendarFile)
    }

    func testICSAllDayCancelledAndPastAreHandled() {
        let future = ref.addingTimeInterval(10 * 86_400)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "en_US_POSIX")
        let day = f.string(from: future)
        let allDay = "BEGIN:VEVENT\nSUMMARY:Holiday\nDTSTART;VALUE=DATE:\(day)\nEND:VEVENT"
        XCTAssertTrue(ICSParser.events(from: allDay, sourceMessageID: "m", referenceDate: ref)[0].isAllDay)

        let cancelled = "BEGIN:VEVENT\nSUMMARY:X\nSTATUS:CANCELLED\nDTSTART:\(utcStamp(future))\nEND:VEVENT"
        XCTAssertTrue(ICSParser.events(from: cancelled, sourceMessageID: "m", referenceDate: ref).isEmpty)

        let past = "BEGIN:VEVENT\nSUMMARY:Old\nDTSTART:\(utcStamp(ref.addingTimeInterval(-30 * 86_400)))\nEND:VEVENT"
        XCTAssertTrue(ICSParser.events(from: past, sourceMessageID: "m", referenceDate: ref).isEmpty)

        let methodCancel = "METHOD:CANCEL\nBEGIN:VEVENT\nSUMMARY:X\nDTSTART:\(utcStamp(future))\nEND:VEVENT"
        XCTAssertTrue(ICSParser.events(from: methodCancel, sourceMessageID: "m", referenceDate: ref).isEmpty)
    }

    // MARK: Date detection in text (uses Apple's detector; assumes an English-language device)

    func testDateExtractorFindsTimedEventAndIgnoresPastDates() {
        let future = Calendar.current.date(byAdding: .day, value: 20, to: ref)!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy"
        let text = """
        Hello,
        Your appointment is on \(f.string(from: future)) at 2:30 PM at the clinic.
        This replaces the one on January 3, 2001.
        """
        let events = DateEventExtractor.events(in: text, sourceMessageID: "m", referenceDate: ref)
        XCTAssertEqual(events.count, 1)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: events[0].start)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertFalse(events[0].isAllDay)
        XCTAssertTrue(events[0].title.contains("appointment"))
    }

    func testDateWithoutTimeIsAllDay() {
        let future = Calendar.current.date(byAdding: .day, value: 20, to: ref)!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM d, yyyy"
        let text = "Payment due \(f.string(from: future))."
        let events = DateEventExtractor.events(in: text, sourceMessageID: "m", referenceDate: ref)
        XCTAssertEqual(events.first?.isAllDay, true)
    }

    // MARK: docx / zip / html

    private func makeStoredZip(name: String, content: Data) -> Data {
        var d = Data()
        func le16(_ v: Int) { d.append(UInt8(v & 0xff)); d.append(UInt8((v >> 8) & 0xff)) }
        func le32(_ v: Int) { le16(v & 0xffff); le16((v >> 16) & 0xffff) }
        let nameData = Data(name.utf8)
        le32(0x0403_4b50); le16(20); le16(0); le16(0); le16(0); le16(0); le32(0)
        le32(content.count); le32(content.count); le16(nameData.count); le16(0)
        d.append(nameData); d.append(content)
        let cdOffset = d.count
        le32(0x0201_4b50); le16(20); le16(20); le16(0); le16(0); le16(0); le16(0); le32(0)
        le32(content.count); le32(content.count); le16(nameData.count); le16(0); le16(0); le16(0); le16(0); le32(0); le32(0)
        d.append(nameData)
        let cdSize = d.count - cdOffset
        le32(0x0605_4b50); le16(0); le16(0); le16(1); le16(1); le32(cdSize); le32(cdOffset); le16(0)
        return d
    }

    func testDocxTextExtraction() throws {
        let xml = #"<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p><w:p><w:r><w:t>World</w:t></w:r></w:p></w:body></w:document>"#
        let zip = makeStoredZip(name: "word/document.xml", content: Data(xml.utf8))
        XCTAssertEqual(try DocxReader.text(from: zip), "Hello\nWorld")
        XCTAssertThrowsError(try DocxReader.text(from: Data("not a zip".utf8)))
    }

    func testHTMLStripping() {
        let html = "<html><head><style>p{color:red}</style></head><body><p>Hi&nbsp;there &amp; welcome</p><p>Line two<br>three</p></body></html>"
        XCTAssertEqual(HTMLText.strip(html), "Hi there & welcome\nLine two\nthree")
    }

    // MARK: Analyzer + store

    func testAnalyzerCombinesBodyAndCalendarAttachmentWithoutDuplicates() async {
        let acc = MailAccount(kind: .gmail, emailAddress: "a@b.c", label: "A", colorIndex: 0)
        let start = Calendar.current.date(byAdding: .day, value: 5, to: ref)!
        let ics = "BEGIN:VEVENT\nSUMMARY:Review\nDTSTART:\(utcStamp(start))\nEND:VEVENT"
        let att = AttachmentInfo(id: "a1", filename: "i.ics", mimeType: "text/calendar", byteCount: ics.count, kind: .calendar)
        let big = AttachmentInfo(id: "a2", filename: "huge.pdf", mimeType: "application/pdf", byteCount: 99_000_000, kind: .pdf)
        let msg = MailMessage(accountID: acc.id, providerMessageID: "m1", from: MailAddress(address: "x@y.z"),
                              subject: "Review", snippet: "", receivedAt: ref, attachments: [att, big])
        let provider = MockMailProvider(account: acc, messages: [msg], bodies: ["m1": "See invite."],
                                        attachmentData: ["a1": Data(ics.utf8)])
        let result = await MessageAnalyzer().analyze(msg, provider: provider, referenceDate: ref)
        XCTAssertEqual(result.body, "See invite.")
        XCTAssertEqual(result.proposals.count, 1)
        XCTAssertEqual(result.proposals[0].title, "Review")
        XCTAssertTrue(result.notes.contains { $0.contains("huge.pdf") })
    }

    func testProposalStoreKeepsStatusAcrossRescans() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = EventProposalStore(directory: dir)
        let start = ref.addingTimeInterval(86_400)
        var first = store.merge([EventProposal(sourceMessageID: "m", title: "Dentist", start: start)], forMessage: "m")[0]
        XCTAssertTrue(store.hasScanned("m"))
        first.status = .dismissed
        first.title = "Edited"
        store.update(first)
        // A re-scan produces a brand-new proposal (new random id) for the same event.
        let again = store.merge([EventProposal(sourceMessageID: "m", title: "Dentist", start: start)], forMessage: "m")
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again[0].status, .dismissed)
        XCTAssertEqual(again[0].title, "Edited")
        XCTAssertEqual(store.all().count, 1)
    }

    func testDeadlinePhrasesUseTheDeadlineDateNotToday() {
        let future = Calendar.current.date(byAdding: .day, value: 20, to: ref)!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMMM d, yyyy"
        for phrase in ["Payment due", "Please confirm by", "Offer valid until"] {
            let events = DateEventExtractor.events(in: "\(phrase) \(f.string(from: future)).", sourceMessageID: "m", referenceDate: ref)
            XCTAssertEqual(events.count, 1, phrase)
            if let e = events.first {
                XCTAssertTrue(Calendar.current.isDate(e.start, inSameDayAs: future), "\(phrase) -> \(e.start)")
                XCTAssertNil(e.end, phrase)
            }
        }
    }
}
