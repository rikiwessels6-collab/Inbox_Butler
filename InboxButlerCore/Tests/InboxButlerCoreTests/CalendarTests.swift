import XCTest
@testable import InboxButlerCore

final class CalendarTests: XCTestCase {
    private let start = Calendar.current.date(byAdding: .day, value: 3, to: Date())!

    private func proposal(_ title: String, at date: Date, hours: Double = 1, allDay: Bool = false) -> EventProposal {
        EventProposal(sourceMessageID: "m", title: title, start: date, end: date.addingTimeInterval(hours * 3600), isAllDay: allDay)
    }
    private func existing(_ title: String, at date: Date, hours: Double = 1, allDay: Bool = false, cal: String = "Family") -> ExistingEvent {
        ExistingEvent(title: title, calendarTitle: cal, start: date, end: date.addingTimeInterval(hours * 3600), isAllDay: allDay)
    }

    func testDuplicateIsRecognisedDespiteCaseAndSpacing() {
        let result = CalendarOverlapChecker.classify(proposal("Swimming  lesson", at: start),
                                                     existing: [existing("swimming lesson", at: start)])
        XCTAssertNotNil(result.duplicate)
        XCTAssertTrue(result.overlaps.isEmpty)
    }

    func testClashingEventIsReportedButIsNotADuplicate() {
        let clash = existing("Football", at: start.addingTimeInterval(1800))
        let after = existing("Dinner", at: start.addingTimeInterval(4 * 3600))
        let result = CalendarOverlapChecker.classify(proposal("Dentist", at: start), existing: [clash, after])
        XCTAssertNil(result.duplicate)
        XCTAssertEqual(result.overlaps.map(\.title), ["Football"])
    }

    func testAllDayItemsDoNotCountAsClashesForTimedEvents() {
        let holiday = existing("School holiday", at: Calendar.current.startOfDay(for: start), hours: 24, allDay: true)
        XCTAssertTrue(CalendarOverlapChecker.classify(proposal("Dentist", at: start), existing: [holiday]).overlaps.isEmpty)
    }

    func testCalendarDisplayName() {
        XCTAssertEqual(CalendarInfo(id: "1", title: "Family", sourceTitle: "iCloud").displayName, "iCloud · Family")
        XCTAssertEqual(CalendarInfo(id: "2", title: "Home", sourceTitle: "Home").displayName, "Home")
        XCTAssertEqual(CalendarInfo(id: "3", title: "Work", sourceTitle: "").displayName, "Work")
    }
}
