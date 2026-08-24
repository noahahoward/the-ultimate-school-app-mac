import XCTest
@testable import Locker

/// What a break does to the rotation is a district's choice, not a fact.
final class ABResetTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)))
    }

    /// Mon 31 Aug 2026 starts the year on an A day.
    private func config(resets: [ABReset] = [], off: [Date] = []) throws -> ScheduleConfig {
        ScheduleConfig(
            kind: .alternatingAB,
            abAnchorDate: try day(2026, 8, 31),
            abAnchorIsA: true,
            abResets: resets,
            noSchoolDays: off,
            firstDayOfSchool: try day(2026, 8, 31)
        )
    }

    func testByDefaultADayOffDoesNotAdvanceTheRotation() throws {
        // Tue 1 Sep off: Wed 2 Sep takes the letter Tuesday would have had.
        let plain = try config()
        let withDayOff = try config(off: [try day(2026, 9, 1)])
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2026, 9, 1), config: plain, calendar: calendar), .b)
        XCTAssertNil(ScheduleEngine.letter(for: try day(2026, 9, 1), config: withDayOff, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2026, 9, 2), config: withDayOff, calendar: calendar), .b)
    }

    func testARestartPutsTheNamedLetterOnThatDay() throws {
        let resets = [ABReset(date: try day(2027, 1, 4), isA: true)]
        let config = try config(resets: resets)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2027, 1, 4), config: config, calendar: calendar), .a)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2027, 1, 5), config: config, calendar: calendar), .b)
    }

    func testARestartOverridesWhateverTheCountWouldHaveGiven() throws {
        let plain = try config()
        let onThatDay = ScheduleEngine.letter(for: try day(2027, 1, 4), config: plain, calendar: calendar)
        // Restart on the letter it would *not* have had, and it must take it.
        let opposite = onThatDay == .a ? false : true
        let config = try config(resets: [ABReset(date: try day(2027, 1, 4), isA: opposite)])
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2027, 1, 4), config: config, calendar: calendar),
                       opposite ? .a : .b)
    }

    func testDaysBeforeARestartAreLeftAlone() throws {
        let plain = try config()
        let config = try config(resets: [ABReset(date: try day(2027, 1, 4), isA: false)])
        for offset in 0..<20 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: try day(2026, 9, 1)))
            XCTAssertEqual(ScheduleEngine.letter(for: date, config: plain, calendar: calendar),
                           ScheduleEngine.letter(for: date, config: config, calendar: calendar),
                           "\(date) changed on the far side of a later restart")
        }
    }

    func testTheLatestRestartBeforeADayGoverns() throws {
        let config = try config(resets: [
            ABReset(date: try day(2026, 10, 5), isA: false),
            ABReset(date: try day(2027, 1, 4), isA: true),
        ])
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2026, 10, 5), config: config, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2027, 1, 4), config: config, calendar: calendar), .a)
    }

    func testARestartLandingOnADayOffMovesToTheNextRealDay() throws {
        // Mon 4 Jan is still a holiday; term resumes Tue 5 Jan on an A day.
        let config = try config(resets: [ABReset(date: try day(2027, 1, 4), isA: true)],
                                off: [try day(2027, 1, 4)])
        XCTAssertNil(ScheduleEngine.letter(for: try day(2027, 1, 4), config: config, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.letter(for: try day(2027, 1, 5), config: config, calendar: calendar), .a)
    }
}
