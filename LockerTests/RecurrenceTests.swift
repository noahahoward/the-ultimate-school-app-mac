import XCTest
@testable import Locker

final class RecurrenceTests: XCTestCase {

    let calendar = TestClock.calendar
    lazy var monday = TestClock.date(2026, 9, 7)

    func testRepeatsLandAWeekApart() {
        let dates = Recurrence.weekly(after: monday, count: 3, calendar: calendar)
        XCTAssertEqual(dates, [
            TestClock.date(2026, 9, 14),
            TestClock.date(2026, 9, 21),
            TestClock.date(2026, 9, 28),
        ])
    }

    func testTheOriginalIsNotRepeated() {
        let dates = Recurrence.weekly(after: monday, count: 2, calendar: calendar)
        XCTAssertFalse(dates.contains(monday), "the assignment being edited is not a copy of itself")
    }

    func testRepeatsKeepTheSameWeekday() {
        let dates = Recurrence.weekly(after: monday, count: 5, calendar: calendar)
        let weekdays = Set(dates.map { calendar.component(.weekday, from: $0) })
        XCTAssertEqual(weekdays, [calendar.component(.weekday, from: monday)])
    }

    func testNoRepeatsRequested() {
        XCTAssertTrue(Recurrence.weekly(after: monday, count: 0, calendar: calendar).isEmpty)
        XCTAssertTrue(Recurrence.weekly(after: monday, count: -3, calendar: calendar).isEmpty)
    }

    func testRepeatsAreCapped() {
        let dates = Recurrence.weekly(after: monday, count: 500, calendar: calendar)
        XCTAssertEqual(dates.count, Recurrence.maximumRepeats)
    }

    func testRepeatsStopAtTheEndOfTheSchoolYear() {
        let dates = Recurrence.weekly(
            after: monday, count: 10,
            notLaterThan: TestClock.date(2026, 10, 5),
            calendar: calendar
        )
        XCTAssertEqual(dates.last, TestClock.date(2026, 10, 5))
        XCTAssertEqual(dates.count, 4)
    }

    func testNoEndDateMeansNoCutoff() {
        let dates = Recurrence.weekly(after: monday, count: 4, notLaterThan: nil, calendar: calendar)
        XCTAssertEqual(dates.count, 4)
    }
}
