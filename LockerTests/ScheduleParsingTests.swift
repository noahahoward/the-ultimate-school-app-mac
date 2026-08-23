import XCTest
@testable import Locker

/// Driven by the exact text Vision reads off a real Skyward schedule, OCR
/// mistakes included: "SPANISH 21", "BIOLOGY I!", "HONORS ENGLISH 91".
final class ScheduleParsingTests: XCTestCase {

    func line(_ text: String, y: Double) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: 0.04, y: y, width: 0.4, height: 0.02))
    }

    /// Transcribed verbatim from the screenshot, top to bottom.
    var skywardSchedule: OCRResult {
        let rows: [(String, Double)] = [
            ("SPANISH 21", 0.981), ("Period 1 - SEMESTER 1", 0.961),
            ("SPANISH 2 I!", 0.911), ("Period 1 - SEMESTER 2", 0.889),
            ("FOUND HEALTH/FIT I", 0.839), ("Period 2 - SEMESTER 1", 0.816),
            ("AP HUMAN GEO II", 0.768), ("Period 2 - SEMESTER 2", 0.746),
            ("BIOLOGY I", 0.697), ("Period 3 - SEMESTER 1", 0.674),
            ("BIOLOGY I!", 0.626), ("Period 3 - SEMESTER 2", 0.604),
            ("ALG 2 FOR PRECALC I", 0.554), ("Period 4 - SEMESTER 1", 0.532),
            ("ALG 2 FOR PRECALC II", 0.484), ("Period 4 - SEMESTER 2", 0.461),
            ("HONORS ENGLISH 91", 0.411), ("Period 6 - SEMESTER 1", 0.390),
            ("HONORS ENGLISH 9 II", 0.341), ("Period 6 - SEMESTER 2", 0.320),
            ("9TH GRADE SUCCESS", 0.270), ("Period 7 - SEMESTER 1", 0.247),
            ("FOUND HEALTH/FIT II", 0.199), ("Period 7 - SEMESTER 2", 0.177),
            ("AP HUMAN GEO I", 0.126), ("Period 8 - SEMESTER 1", 0.105),
            ("ENGINEERING CAD", 0.056), ("Period 8 - SEMESTER 2", 0.035),
        ]
        return OCRResult(lines: rows.map { line($0.0, y: $0.1) })
    }

    var parsed: [ClassDraft] { ScheduleParsing.rows(from: skywardSchedule) }

    func testEveryClassIsFound() {
        XCTAssertEqual(parsed.count, 14)
    }

    func testPeriodsAndSemestersAreRead() {
        let summary = parsed.map { "\($0.period ?? 0)/\($0.semester)" }
        XCTAssertEqual(summary, [
            "1/1", "1/2", "2/1", "2/2", "3/1", "3/2", "4/1",
            "4/2", "6/1", "6/2", "7/1", "7/2", "8/1", "8/2",
        ])
    }

    func testOCRMangledRomanNumeralsAreStrippedFromNames() {
        let names = parsed.map(\.name)
        XCTAssertEqual(names, [
            "SPANISH 2", "SPANISH 2",
            "FOUND HEALTH/FIT", "AP HUMAN GEO",
            "BIOLOGY", "BIOLOGY",
            "ALG 2 FOR PRECALC", "ALG 2 FOR PRECALC",
            "HONORS ENGLISH 9", "HONORS ENGLISH 9",
            "9TH GRADE SUCCESS", "FOUND HEALTH/FIT",
            "AP HUMAN GEO", "ENGINEERING CAD",
        ])
    }

    func testTheTwoSemestersHoldDifferentClasses() {
        let first = parsed.filter { $0.semester == 1 }.map(\.name)
        let second = parsed.filter { $0.semester == 2 }.map(\.name)
        XCTAssertTrue(first.contains("9TH GRADE SUCCESS"))
        XCTAssertFalse(second.contains("9TH GRADE SUCCESS"))
        XCTAssertTrue(second.contains("ENGINEERING CAD"))
        XCTAssertFalse(first.contains("ENGINEERING CAD"))
    }

    func testTheSkippedLunchPeriodIsNotInvented() {
        XCTAssertFalse(parsed.contains { $0.period == 5 })
    }

    // MARK: - Name handling in isolation

    func testBaseNameStripsNumeralShapes() {
        XCTAssertEqual(ScheduleParsing.baseName("BIOLOGY II"), "BIOLOGY")
        XCTAssertEqual(ScheduleParsing.baseName("BIOLOGY I!"), "BIOLOGY")
        XCTAssertEqual(ScheduleParsing.baseName("SPANISH 21"), "SPANISH 2")
        XCTAssertEqual(ScheduleParsing.baseName("HONORS ENGLISH 91"), "HONORS ENGLISH 9")
        XCTAssertEqual(ScheduleParsing.baseName("9TH GRADE SUCCESS"), "9TH GRADE SUCCESS")
        XCTAssertEqual(ScheduleParsing.baseName("ENGINEERING CAD"), "ENGINEERING CAD")
    }

    func testAnUnpairedCourseNumberIsLeftAlone() {
        // "Algebra 1" appears once, so nothing proves the 1 is a semester marker.
        let ocr = OCRResult(lines: [
            line("ALGEBRA 1", y: 0.9), line("Period 2 - SEMESTER 1", y: 0.88),
            line("CHOIR", y: 0.8), line("Period 3 - SEMESTER 1", y: 0.78),
        ])
        XCTAssertEqual(ScheduleParsing.rows(from: ocr).map(\.name), ["ALGEBRA 1", "CHOIR"])
    }

    // MARK: - Other schedule formats

    func testPeriodPatterns() {
        XCTAssertEqual(ScheduleParsing.period(in: "Period 3 - SEMESTER 1"), 3)
        XCTAssertEqual(ScheduleParsing.period(in: "Per 4 · Rm 118"), 4)
        XCTAssertEqual(ScheduleParsing.period(in: "3rd Period"), 3)
        XCTAssertNil(ScheduleParsing.period(in: "SPANISH 2"))
        XCTAssertNil(ScheduleParsing.period(in: "Period 99"))
    }

    func testRoomAndTimesWhenTheSchedulePrintsThem() {
        let ocr = OCRResult(lines: [
            line("BIOLOGY", y: 0.9),
            line("Period 3 - Room 204 - 9:02 AM - 9:54 AM", y: 0.88),
        ])
        let row = ScheduleParsing.rows(from: ocr).first
        XCTAssertEqual(row?.room, "204")
        XCTAssertEqual(row?.startMinutes, 9 * 60 + 2)
        XCTAssertEqual(row?.endMinutes, 9 * 60 + 54)
    }

    func testHeadersAreNotMistakenForCourses() {
        let ocr = OCRResult(lines: [
            line("Schedule", y: 0.95),
            line("BIOLOGY", y: 0.9),
            line("Period 3 - SEMESTER 1", y: 0.88),
        ])
        XCTAssertEqual(ScheduleParsing.rows(from: ocr).map(\.name), ["BIOLOGY"])
    }

    func testAPageWithNoScheduleYieldsNothing() {
        let ocr = OCRResult(lines: [line("Welcome back", y: 0.9), line("No results", y: 0.8)])
        XCTAssertTrue(ScheduleParsing.rows(from: ocr).isEmpty)
    }
}

/// The semester filter that makes a two-semester timetable behave.
final class SemesterScheduleTests: XCTestCase {

    let calendar = TestClock.calendar

    var config: ScheduleConfig {
        ScheduleConfig(
            firstDayOfSchool: TestClock.date(2026, 8, 24),
            lastDayOfSchool: TestClock.date(2027, 5, 28),
            secondSemesterStart: TestClock.date(2027, 1, 5)
        )
    }

    func testOnlyTheRunningSemestersClassesMeet() {
        let classes = [
            TestClass("9th Grade Success", semester: 1),
            TestClass("Engineering CAD", semester: 2),
            TestClass("Advisory", semester: 0),
        ]
        let inFall = ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 15), from: classes, config: config, calendar: calendar)
        XCTAssertEqual(Set(inFall.map(\.name)), ["9th Grade Success", "Advisory"])

        let inSpring = ScheduleEngine.classes(meetingOn: TestClock.date(2027, 2, 10), from: classes, config: config, calendar: calendar)
        XCTAssertEqual(Set(inSpring.map(\.name)), ["Engineering CAD", "Advisory"])
    }

    func testWithoutASemesterDateEverythingRunsAllYear() {
        let plain = ScheduleConfig()
        let classes = [TestClass("Fall only", semester: 1), TestClass("Spring only", semester: 2)]
        let meeting = ScheduleEngine.classes(meetingOn: TestClock.date(2026, 9, 15), from: classes, config: plain, calendar: calendar)
        XCTAssertEqual(meeting.count, 2)
    }

    func testSemesterBoundary() {
        XCTAssertEqual(ScheduleEngine.semester(on: TestClock.date(2027, 1, 4), config: config, calendar: calendar), 1)
        XCTAssertEqual(ScheduleEngine.semester(on: TestClock.date(2027, 1, 5), config: config, calendar: calendar), 2)
    }
}

extension ScheduleParsingTests {

    func testTimesAreFoundAnywhereInTheLine() {
        XCTAssertEqual(ScheduleParsing.clockTimes(in: "Period 3 - Room 204 - 9:02 AM - 9:54 AM"),
                       [9 * 60 + 2, 9 * 60 + 54])
        XCTAssertEqual(ScheduleParsing.clockTimes(in: "9:02-9:54"), [9 * 60 + 2, 9 * 60 + 54])
    }

    func testAnAfternoonClassDoesNotAppearToEndBeforeItStarts() {
        // "12:40 - 1:32" is lunch-hour to early afternoon, not a 23-hour class.
        let range = ScheduleParsing.timeRange(in: "Period 5 - 12:40 - 1:32")
        XCTAssertEqual(range?.start, 12 * 60 + 40)
        XCTAssertEqual(range?.end, 13 * 60 + 32)
    }

    func testExplicitMeridiemIsRespected() {
        let range = ScheduleParsing.timeRange(in: "1:15 PM - 2:05 PM")
        XCTAssertEqual(range?.start, 13 * 60 + 15)
        XCTAssertEqual(range?.end, 14 * 60 + 5)
    }

    func testALineWithNoTimesHasNoRange() {
        XCTAssertNil(ScheduleParsing.timeRange(in: "Period 1 - SEMESTER 1"))
    }
}

/// Confirms a schedule screenshot is routed to the schedule path, not treated as
/// one very confusing assignment.
final class ScreenshotRoutingTests: XCTestCase {

    func line(_ text: String, y: Double) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: 0.04, y: y, width: 0.4, height: 0.02))
    }

    func testATimetableIsRecognisedAsASchedule() {
        let ocr = OCRResult(lines: [
            line("BIOLOGY I", y: 0.9), line("Period 3 - SEMESTER 1", y: 0.88),
            line("SPANISH 2 I", y: 0.8), line("Period 1 - SEMESTER 1", y: 0.78),
        ])
        XCTAssertEqual(ScheduleParsing.rows(from: ocr).count, 2)
    }

    func testAnAssignmentPageIsNotMistakenForASchedule() {
        // One stray "Period 3" on an assignment page must not trigger the
        // schedule path, which is why two rows are required.
        let ocr = OCRResult(lines: [
            line("Summer Homework Assignment 2026", y: 0.95),
            line("Serena Sturgill • Jun 17", y: 0.90),
            line("Period 3", y: 0.85),
            line("4 points | Due Aug 26", y: 0.80),
        ])
        XCTAssertLessThan(ScheduleParsing.rows(from: ocr).count, 2)
    }

    // MARK: - Term markers on class names

    func testTheRomanNumeralForTheSemesterIsDropped() {
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("BIOLOGY I", semester: 1), "BIOLOGY")
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("BIOLOGY II", semester: 2), "BIOLOGY")
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("HONORS ENGLISH 9 I", semester: 1),
                       "HONORS ENGLISH 9")
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("ALG 2 FOR PRECALC II", semester: 2),
                       "ALG 2 FOR PRECALC")
    }

    func testASpelledOutTermIsDropped() {
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("OFF CAMPUS SEMINARY SEM 1", semester: 1),
                       "OFF CAMPUS SEMINARY")
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("STUDY HALL S2", semester: 2),
                       "STUDY HALL")
    }

    func testANumeralNamingTheLevelIsKept() {
        // Spanish II in the first half of the year is a level, not a term.
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("SPANISH II", semester: 1), "SPANISH II")
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("LATIN I", semester: 2), "LATIN I")
    }

    func testABareNumberIsNeverTakenForATerm() {
        // Otherwise Spanish 2 in the second semester would become Spanish.
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("SPANISH 2", semester: 2), "SPANISH 2")
    }

    func testAYearLongClassKeepsItsName() {
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("BAND I", semester: 0), "BAND I")
    }

    func testANameThatIsOnlyAMarkerSurvives() {
        XCTAssertEqual(ScheduleParsing.nameWithoutTermMarker("I", semester: 1), "I")
    }
}
