import XCTest
@testable import Locker

final class ScheduleEngineTests: XCTestCase {

    let calendar = TestClock.calendar

    // Tue Sep 1 2026 is the anchor A day in most of these tests.
    lazy var abConfig = ScheduleConfig(
        kind: .alternatingAB,
        schoolDays: Weekdays.schoolWeek,
        abAnchorDate: TestClock.date(2026, 9, 1),
        abAnchorIsA: true
    )

    func testWeekendIsNotASchoolDay() {
        let config = ScheduleConfig()
        XCTAssertTrue(ScheduleEngine.isSchoolDay(TestClock.date(2026, 9, 3), config: config, calendar: calendar))
        XCTAssertFalse(ScheduleEngine.isSchoolDay(TestClock.date(2026, 9, 5), config: config, calendar: calendar))
    }

    func testHolidayIsNotASchoolDay() {
        let config = ScheduleConfig(noSchoolDays: [TestClock.date(2026, 9, 7)])
        XCTAssertFalse(ScheduleEngine.isSchoolDay(TestClock.date(2026, 9, 7), config: config, calendar: calendar))
    }

    func testDatesOutsideTheSchoolYearAreNotSchoolDays() {
        let config = ScheduleConfig(
            firstDayOfSchool: TestClock.date(2026, 8, 24),
            lastDayOfSchool: TestClock.date(2027, 5, 28)
        )
        XCTAssertFalse(ScheduleEngine.isSchoolDay(TestClock.date(2026, 8, 20), config: config, calendar: calendar))
        XCTAssertFalse(ScheduleEngine.isSchoolDay(TestClock.date(2027, 6, 10), config: config, calendar: calendar))
    }

    func testABLettersAlternateAcrossSchoolDays() {
        // Tue A, Wed B, Thu A, Fri B, then Monday picks up at A.
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 1), config: abConfig, calendar: calendar), .a)
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 2), config: abConfig, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 3), config: abConfig, calendar: calendar), .a)
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 4), config: abConfig, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 7), config: abConfig, calendar: calendar), .a)
    }

    func testWeekendsHaveNoLetter() {
        XCTAssertNil(ScheduleEngine.letter(for: TestClock.date(2026, 9, 5), config: abConfig, calendar: calendar))
    }

    func testHolidayShiftsTheLetterSequence() {
        // A day off means the letters do not advance across it.
        var config = abConfig
        config.noSchoolDays = [TestClock.date(2026, 9, 2)]
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 1), config: config, calendar: calendar), .a)
        XCTAssertNil(ScheduleEngine.letter(for: TestClock.date(2026, 9, 2), config: config, calendar: calendar))
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 9, 3), config: config, calendar: calendar), .b)
    }

    func testLettersWorkBeforeTheAnchor() {
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 8, 31), config: abConfig, calendar: calendar), .b)
        XCTAssertEqual(ScheduleEngine.letter(for: TestClock.date(2026, 8, 28), config: abConfig, calendar: calendar), .a)
    }

    func testNoLetterWhenScheduleIsWeekly() {
        let config = ScheduleConfig(kind: .weekly, abAnchorDate: TestClock.date(2026, 9, 1))
        XCTAssertNil(ScheduleEngine.letter(for: TestClock.date(2026, 9, 3), config: config, calendar: calendar))
    }

    // MARK: - Meetings

    func testClassesMeetingOnADayRespectABDesignation() {
        let classes = [
            TestClass("Biology", ab: .a, start: 8 * 60, end: 9 * 60),
            TestClass("Art", ab: .b, start: 8 * 60, end: 9 * 60),
            TestClass("Advisory", ab: .both, start: 7 * 60 + 40, end: 7 * 60 + 55),
        ]
        // Sep 1 is an A day.
        let aDay = ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 1), from: classes, config: abConfig, calendar: calendar)
        XCTAssertEqual(aDay.map(\.name), ["Advisory", "Biology"])

        let bDay = ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 2), from: classes, config: abConfig, calendar: calendar)
        XCTAssertEqual(bDay.map(\.name), ["Advisory", "Art"])
    }

    func testClassesOnlyMeetOnTheirWeekdays() {
        let classes = [TestClass("Gym", days: [3, 5])] // Tue + Thu
        let config = ScheduleConfig()
        XCTAssertEqual(ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 1), from: classes, config: config, calendar: calendar).count, 1)
        XCTAssertEqual(ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 2), from: classes, config: config, calendar: calendar).count, 0)
    }

    func testArchivedClassesAreHidden() {
        let classes = [TestClass("Old Elective", archived: true)]
        XCTAssertTrue(ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 1), from: classes, config: ScheduleConfig(), calendar: calendar).isEmpty)
    }

    func testOrderingFallsBackFromTimeToPeriodToName() {
        let classes = [
            TestClass("Zoology", period: 2),
            TestClass("Anatomy", period: 1),
            TestClass("Homeroom", start: 7 * 60 + 30),
            TestClass("Unscheduled"),
        ]
        let ordered = ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 1), from: classes, config: ScheduleConfig(), calendar: calendar)
        XCTAssertEqual(ordered.map(\.name), ["Homeroom", "Anatomy", "Zoology", "Unscheduled"])
    }

    func testNowAndNext() {
        let classes = [
            TestClass("First", start: 8 * 60, end: 9 * 60),
            TestClass("Second", start: 9 * 60 + 10, end: 10 * 60),
            TestClass("Third", start: 10 * 60 + 10, end: 11 * 60),
        ]
        let moment = TestClock.date(2026, 9, 1, 9, 30)
        let result = ScheduleEngine.nowAndNext(at: moment, from: classes, config: ScheduleConfig(), calendar: calendar)
        XCTAssertEqual(result.now?.name, "Second")
        XCTAssertEqual(result.next?.name, "Third")
    }

    func testNowAndNextBetweenClasses() {
        let classes = [
            TestClass("First", start: 8 * 60, end: 9 * 60),
            TestClass("Second", start: 9 * 60 + 10, end: 10 * 60),
        ]
        let moment = TestClock.date(2026, 9, 1, 9, 5)
        let result = ScheduleEngine.nowAndNext(at: moment, from: classes, config: ScheduleConfig(), calendar: calendar)
        XCTAssertNil(result.now)
        XCTAssertEqual(result.next?.name, "Second")
    }

    func testNextSchoolDaySkipsWeekend() {
        let config = ScheduleConfig()
        // Friday Sep 4 -> next school day from Saturday is Monday Sep 7.
        XCTAssertEqual(
            ScheduleEngine.nextSchoolDay(onOrAfter: TestClock.date(2026, 9, 5), config: config, calendar: calendar),
            TestClock.date(2026, 9, 7)
        )
    }
}
