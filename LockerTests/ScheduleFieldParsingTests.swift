import XCTest
@testable import Locker

/// Formats other schools print. The pattern reader only knows the shape one
/// district uses, so these are the conversions the model route depends on.
final class ScheduleFieldParsingTests: XCTestCase {

    // MARK: - Periods

    func testPeriodFromTheFormsSchedulesPrint() {
        XCTAssertEqual(ScheduleFieldParsing.period(from: "Period 3"), 3)
        XCTAssertEqual(ScheduleFieldParsing.period(from: "P3"), 3)
        XCTAssertEqual(ScheduleFieldParsing.period(from: "3rd"), 3)
        XCTAssertEqual(ScheduleFieldParsing.period(from: "3"), 3)
        XCTAssertEqual(ScheduleFieldParsing.period(from: "Per 11"), 11)
        XCTAssertNil(ScheduleFieldParsing.period(from: ""))
        XCTAssertNil(ScheduleFieldParsing.period(from: "Advisory"))
    }

    // MARK: - Terms

    func testTermsMapToSemesters() {
        XCTAssertEqual(ScheduleFieldParsing.semester(from: "SEMESTER 1"), 1)
        XCTAssertEqual(ScheduleFieldParsing.semester(from: "S2"), 2)
        XCTAssertEqual(ScheduleFieldParsing.semester(from: "Fall"), 1)
        XCTAssertEqual(ScheduleFieldParsing.semester(from: "Spring Term"), 2)
        XCTAssertEqual(ScheduleFieldParsing.semester(from: "Full Year"), 0)
        // Nothing printed means it runs all year, not that it runs never.
        XCTAssertEqual(ScheduleFieldParsing.semester(from: ""), 0)
    }

    // MARK: - Meeting days

    func testDayLettersInEveryCommonForm() {
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "M W F"), [2, 4, 6])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "MWF"), [2, 4, 6])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "Mon/Wed/Fri"), [2, 4, 6])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "Tu Th"), [3, 5])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "M-F"), Weekdays.schoolWeek)
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "Daily"), Weekdays.schoolWeek)
    }

    func testThursdayIsNotReadAsTuesday() {
        // "Th" has to beat "T", or every Thursday class lands on a Tuesday.
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "Th"), [5])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "T"), [3])
        XCTAssertEqual(ScheduleFieldParsing.weekdays(from: "MTWThF"), Weekdays.schoolWeek)
    }

    func testNoDaysPrintedMeansNoOpinion() {
        XCTAssertNil(ScheduleFieldParsing.weekdays(from: ""))
        XCTAssertNil(ScheduleFieldParsing.weekdays(from: "   "))
        XCTAssertNil(ScheduleFieldParsing.weekdays(from: "1234"))
    }

    // MARK: - Times

    func testTimesFromAFreestandingRange() {
        let range = ScheduleFieldParsing.times(from: "9:02-9:54")
        XCTAssertEqual(range?.start, 9 * 60 + 2)
        XCTAssertEqual(range?.end, 9 * 60 + 54)
        XCTAssertNil(ScheduleFieldParsing.times(from: "Period 3"))
    }
}

/// Pinned to what the on-device model actually returned for unfamiliar schedule
/// layouts. It sometimes puts the wrong column in a field, and these make sure a
/// wrong column produces nothing rather than a plausible-looking mistake.
extension ScheduleFieldParsingTests {

    func testATimeInThePeriodFieldIsNotReadAsAPeriod() {
        // The model returned periodText "7:45-8:35 AM" for a schedule with no
        // period column. Taking the leading digits would make that period 7.
        XCTAssertNil(ScheduleFieldParsing.period(from: "7:45-8:35 AM"))
        XCTAssertNil(ScheduleFieldParsing.period(from: "10:30-11:20 AM"))
    }

    func testARoomNumberInThePeriodFieldIsNotReadAsAPeriod() {
        XCTAssertNil(ScheduleFieldParsing.period(from: "210"))
        XCTAssertNil(ScheduleFieldParsing.period(from: "Rm 118"))
    }

    func testABareNumberIsStillAPeriod() {
        XCTAssertEqual(ScheduleFieldParsing.period(from: "3"), 3)
        XCTAssertEqual(ScheduleFieldParsing.period(from: " 7 "), 7)
        XCTAssertEqual(ScheduleFieldParsing.period(from: "3rd"), 3)
    }

    func testTeacherNamesInGradebookOrderStillResolve() {
        // "SMITH, J" is how the column-table schedule printed teachers.
        XCTAssertEqual(ClassMatcher.surname(of: "SMITH, J"), "smith")
        XCTAssertEqual(ClassMatcher.surname(of: "OKAFOR, D"), "okafor")
    }
}
