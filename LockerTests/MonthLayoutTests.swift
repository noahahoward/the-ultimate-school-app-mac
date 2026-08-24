import XCTest
@testable import Locker

final class MonthLayoutTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1 // Sunday, as the app's day letters assume
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    func testEveryRowIsSevenLong() throws {
        for month in 1...12 {
            let weeks = MonthLayout.weeks(of: try date(2026, month, 15), calendar: calendar)
            XCTAssertFalse(weeks.isEmpty, "month \(month) laid out empty")
            for week in weeks {
                XCTAssertEqual(week.count, 7, "month \(month) has a short row")
            }
        }
    }

    func testTheMonthKeepsAllOfItsDaysAndNoOthers() throws {
        let august = try date(2026, 8, 15)
        let days = MonthLayout.weeks(of: august, calendar: calendar).flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(calendar.component(.day, from: days.first!), 1)
        XCTAssertEqual(calendar.component(.day, from: days.last!), 31)
        XCTAssertTrue(days.allSatisfy { calendar.component(.month, from: $0) == 8 })
    }

    func testTheFirstFallsUnderItsOwnWeekdayColumn() throws {
        // August 2026 opens on a Saturday, so six blanks precede it.
        let weeks = MonthLayout.weeks(of: try date(2026, 8, 1), calendar: calendar)
        let leading = weeks[0].prefix { $0 == nil }.count
        XCTAssertEqual(leading, 6)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(weeks[0][6])), 7)
    }

    func testAMonthOpeningOnTheFirstColumnHasNoBlanks() throws {
        // February 2026 opens on a Sunday.
        let weeks = MonthLayout.weeks(of: try date(2026, 2, 10), calendar: calendar)
        XCTAssertNotNil(weeks[0][0])
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(weeks[0][0])), 1)
    }

    func testDaysRunInOrderWithNoRepeats() throws {
        let days = MonthLayout.weeks(of: try date(2026, 8, 1), calendar: calendar)
            .flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(Set(days).count, days.count)
    }

    func testWeekdayInitialsStartWhereTheWeekDoes() {
        var monday = calendar
        monday.firstWeekday = 2
        let sundayFirst = MonthLayout.weekdayInitials(calendar: calendar)
        let mondayFirst = MonthLayout.weekdayInitials(calendar: monday)
        XCTAssertEqual(sundayFirst.count, 7)
        XCTAssertEqual(mondayFirst.count, 7)
        XCTAssertEqual(mondayFirst.first, sundayFirst[1])
        XCTAssertEqual(mondayFirst.last, sundayFirst[0])
    }
}
