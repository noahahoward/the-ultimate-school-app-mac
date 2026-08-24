import XCTest
@testable import Locker

/// Days a school sets aside — an introduction day, a Friday run differently —
/// belong to neither letter and must not disturb the ones around them.
final class AllClassDayTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func day(_ month: Int, _ dayOfMonth: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth)))
    }

    /// Thu 27 Aug 2026 opens the year; Fri 28, then Mon 31, Tue 1 Sep…
    private func config(allClassDates: [Date] = [], allClassWeekdays: Set<Int> = []) throws -> ScheduleConfig {
        ScheduleConfig(
            kind: .alternatingAB,
            abAnchorDate: try day(8, 27),
            abAnchorIsA: true,
            allClassDates: allClassDates,
            allClassWeekdays: allClassWeekdays,
            firstDayOfSchool: try day(8, 27)
        )
    }

    func testWithoutSetAsideDaysTheLettersSimplyAlternate() throws {
        let config = try config()
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 27), config: config, calendar: calendar), .a)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 28), config: config, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 31), config: config, calendar: calendar), .a)
    }

    func testAnIntroductionDayCarriesNoLetter() throws {
        let config = try config(allClassDates: [try day(8, 27)])
        XCTAssertNil(ScheduleEngine.letter(for: try day(8, 27), config: config, calendar: calendar))
        XCTAssertTrue(ScheduleEngine.isAllClassDay(try day(8, 27), config: config, calendar: calendar))
    }

    func testTheLettersStartOnTheFirstDayThatCarriesOne() throws {
        // The anchor is the first day of school, which is an introduction day,
        // so the A the student chose lands on the day after it.
        let config = try config(allClassDates: [try day(8, 27)])
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 28), config: config, calendar: calendar), .a)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 31), config: config, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(9, 1), config: config, calendar: calendar), .a)
    }

    func testADaySetAsideMidYearDoesNotSwapEverythingAfterIt() throws {
        let plain = try config()
        let withBreak = try config(allClassDates: [try day(9, 1)])
        // Tue 1 Sep is set aside; the days around it keep the letters they had.
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 31), config: plain, calendar: calendar),
                       ScheduleEngine.letter(for: try day(8, 31), config: withBreak, calendar: calendar))
        XCTAssertNil(ScheduleEngine.letter(for: try day(9, 1), config: withBreak, calendar: calendar))
        // Wed 2 Sep would have been B; it takes the letter 1 Sep would have had.
        XCTAssertEqual(ScheduleEngine.letter(for: try day(9, 1), config: plain, calendar: calendar),
                       ScheduleEngine.letter(for: try day(9, 2), config: withBreak, calendar: calendar))
    }

    func testEveryFridaySetAsideLeavesTheRestAlternating() throws {
        let config = try config(allClassWeekdays: [6])
        XCTAssertNil(ScheduleEngine.letter(for: try day(8, 28), config: config, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 27), config: config, calendar: calendar), .a)
        // Mon 31 follows Thu 27 as the next lettered day.
        XCTAssertEqual(ScheduleEngine.letter(for: try day(8, 31), config: config, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(9, 1), config: config, calendar: calendar), .a)
    }

    func testASetAsideDayIsStillASchoolDay() throws {
        let config = try config(allClassWeekdays: [6])
        XCTAssertTrue(ScheduleEngine.isSchoolDay(try day(8, 28), config: config, calendar: calendar))
    }

    func testEveryClassMeetsOnADaySetAside() throws {
        let config = try config(allClassDates: [try day(8, 27)])
        let monday = StubClass(daysMask: Weekdays.mask(from: [2]), abDesignation: .a, name: "Choir")
        let bDayOnly = StubClass(daysMask: Weekdays.mask(from: Weekdays.schoolWeek),
                                 abDesignation: .b, name: "Physics")

        let meeting = ScheduleEngine.classes(meetingOn: try day(8, 27), from: [monday, bDayOnly],
                                             config: config, calendar: calendar)
        XCTAssertEqual(Set(meeting.map(\.name)), ["Choir", "Physics"])
    }

    func testAClassFromTheOtherSemesterStillStaysAway() throws {
        var config = try config(allClassDates: [try day(8, 27)])
        // The second half of the 2026-27 year, which begins in January 2027.
        config.secondSemesterStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 5))
        )
        let spring = StubClass(daysMask: Weekdays.mask(from: Weekdays.schoolWeek),
                               abDesignation: .both, name: "Spring Only", semester: 2)
        let meeting = ScheduleEngine.classes(meetingOn: try day(8, 27), from: [spring],
                                             config: config, calendar: calendar)
        XCTAssertTrue(meeting.isEmpty)
    }
}

private struct StubClass: ScheduleItem {
    var daysMask: Int
    var abDesignation: ABDesignation
    var startMinutes: Int? = nil
    var endMinutes: Int? = nil
    var period: Int? = nil
    var name: String
    var isArchived = false
    var semester = 0
}
