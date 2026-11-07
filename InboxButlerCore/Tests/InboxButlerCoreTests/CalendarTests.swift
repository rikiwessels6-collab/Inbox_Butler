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

final class CalendarLayoutTests: XCTestCase {
    private let day = Calendar.current.startOfDay(for: Date())
    private func ev(_ title: String, _ startHour: Double, _ endHour: Double) -> ExistingEvent {
        ExistingEvent(title: title, calendarTitle: "Family", start: day.addingTimeInterval(startHour * 3600),
                      end: day.addingTimeInterval(endHour * 3600), isAllDay: false)
    }

    func testOverlappingEventsGetSeparateLanes() {
        let placed = CalendarLayout.place([ev("A", 9, 11), ev("B", 10, 12), ev("C", 13, 14)])
        let byTitle = Dictionary(uniqueKeysWithValues: placed.map { ($0.event.title, $0) })
        XCTAssertEqual(byTitle["A"]?.lane, 0)
        XCTAssertEqual(byTitle["B"]?.lane, 1)
        XCTAssertEqual(byTitle["A"]?.laneCount, 2)
        XCTAssertEqual(byTitle["B"]?.laneCount, 2)
        // C is separate: full width.
        XCTAssertEqual(byTitle["C"]?.lane, 0)
        XCTAssertEqual(byTitle["C"]?.laneCount, 1)
    }

    func testLaneIsReusedWhenAnEventHasEnded() {
        // A and B overlap; C starts after A ends, so it reuses A's lane.
        let placed = CalendarLayout.place([ev("A", 9, 10), ev("B", 9.5, 12), ev("C", 10.5, 11.5)])
        let byTitle = Dictionary(uniqueKeysWithValues: placed.map { ($0.event.title, $0) })
        XCTAssertEqual(byTitle["C"]?.lane, 0)
        XCTAssertEqual(byTitle["B"]?.lane, 1)
        XCTAssertEqual(byTitle["C"]?.laneCount, 2)
    }

    func testFamilyDoubleBookingStaysVisible() {
        // Two people's events at exactly the same time both show, side by side.
        let placed = CalendarLayout.place([ev("Swimming", 16, 17), ev("Football", 16, 17), ev("Piano", 16, 17)])
        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(Set(placed.map(\.lane)), [0, 1, 2])
        XCTAssertTrue(placed.allSatisfy { $0.laneCount == 3 })
    }

    func testNoEventsAndSingleEvent() {
        XCTAssertTrue(CalendarLayout.place([]).isEmpty)
        let single = CalendarLayout.place([ev("Solo", 8, 9)])
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].laneCount, 1)
    }
}
