import XCTest
@testable import Locker

final class StreaksTests: XCTestCase {

    let calendar = TestClock.calendar
    let config = ScheduleConfig()
    // Thursday.
    lazy var now = TestClock.date(2026, 9, 3, 20, 0)

    func testConsecutiveSchoolDaysCount() {
        let dates = [
            TestClock.date(2026, 9, 1, 16, 0),
            TestClock.date(2026, 9, 2, 16, 0),
            TestClock.date(2026, 9, 3, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 3)
        XCTAssertTrue(summary.didSomethingToday)
    }

    func testWeekendDoesNotBreakAStreak() {
        // Fri Aug 28, then Mon Aug 31, Tue Sep 1 ... nothing over the weekend.
        let dates = [
            TestClock.date(2026, 8, 28, 16, 0),
            TestClock.date(2026, 8, 31, 16, 0),
            TestClock.date(2026, 9, 1, 16, 0),
            TestClock.date(2026, 9, 2, 16, 0),
            TestClock.date(2026, 9, 3, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 5)
    }

    func testHolidayDoesNotBreakAStreak() {
        var holidayConfig = config
        holidayConfig.noSchoolDays = [TestClock.date(2026, 9, 2)]
        let dates = [
            TestClock.date(2026, 9, 1, 16, 0),
            TestClock.date(2026, 9, 3, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: holidayConfig, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 2)
    }

    func testMissedSchoolDayBreaksTheStreak() {
        let dates = [
            TestClock.date(2026, 9, 1, 16, 0),
            TestClock.date(2026, 9, 3, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 1)
    }

    func testStreakSurvivesUntilTodayIsOver() {
        // Nothing done today yet, but yesterday and the day before were.
        let dates = [
            TestClock.date(2026, 9, 1, 16, 0),
            TestClock.date(2026, 9, 2, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 2)
        XCTAssertFalse(summary.didSomethingToday)
    }

    func testEmptyHistory() {
        let summary = Streaks.summary(completionDates: [], config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 0)
        XCTAssertEqual(summary.best, 0)
        XCTAssertFalse(summary.didSomethingToday)
    }

    func testBestRemembersAnOlderLongerRun() {
        let dates = [
            // A four-day run in August.
            TestClock.date(2026, 8, 24, 16, 0),
            TestClock.date(2026, 8, 25, 16, 0),
            TestClock.date(2026, 8, 26, 16, 0),
            TestClock.date(2026, 8, 27, 16, 0),
            // A one-day run now.
            TestClock.date(2026, 9, 3, 16, 0),
        ]
        let summary = Streaks.summary(completionDates: dates, config: config, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 1)
        XCTAssertEqual(summary.best, 4)
    }
}
