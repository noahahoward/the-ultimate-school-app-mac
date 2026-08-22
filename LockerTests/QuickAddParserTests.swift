import XCTest
@testable import Locker

final class QuickAddParserTests: XCTestCase {

    let calendar = TestClock.calendar
    // A Thursday, so weekday math has somewhere to go in both directions.
    lazy var now = TestClock.date(2026, 9, 3, 16, 0)

    lazy var classes: [ClassRef] = [
        ClassRef(id: "bio", name: "Biology I", aliases: ["bio"], startMinutes: 8 * 60 + 15),
        ClassRef(id: "alg", name: "Algebra 2", aliases: ["alg", "math"]),
        ClassRef(id: "hist", name: "World History", aliases: ["wh"]),
        ClassRef(id: "eng", name: "English 9", aliases: ["eng"]),
    ]

    func parse(_ text: String) -> ParsedQuickAdd {
        QuickAddParser.parse(text, classes: classes, now: now, calendar: calendar)
    }

    // MARK: - Class matching

    func testMatchesClassByAlias() {
        let result = parse("bio lab report")
        XCTAssertEqual(result.classID, "bio")
        XCTAssertEqual(result.title, "Lab report")
        XCTAssertEqual(result.type, .lab)
    }

    func testMatchesMultiWordClassNameOverPartial() {
        let result = parse("world history reading")
        XCTAssertEqual(result.classID, "hist")
        XCTAssertEqual(result.title, "Reading")
    }

    func testMatchesClassByPrefixWithoutConfiguredAlias() {
        let result = parse("engl essay")
        XCTAssertEqual(result.classID, "eng")
    }

    func testClassNameWithDigitsIsNotReadAsADate() {
        let result = parse("algebra 2 worksheet")
        XCTAssertEqual(result.classID, "alg")
        XCTAssertEqual(result.title, "Worksheet")
        XCTAssertNil(result.dueAt)
    }

    func testNoClassMatchLeavesClassNil() {
        let result = parse("clean my room")
        XCTAssertNil(result.classID)
        XCTAssertEqual(result.title, "Clean my room")
    }

    // MARK: - Dates

    func testToday() {
        let result = parse("bio hw today")
        XCTAssertEqual(result.dueAt, TestClock.date(2026, 9, 3))
        XCTAssertFalse(result.hasDueTime)
    }

    func testTomorrow() {
        XCTAssertEqual(parse("read ch 4 tomorrow").dueAt, TestClock.date(2026, 9, 4))
    }

    func testWeekdayPicksTheUpcomingOne() {
        // Thursday Sep 3 -> "mon" is Monday Sep 7.
        XCTAssertEqual(parse("essay due mon").dueAt, TestClock.date(2026, 9, 7))
    }

    func testWeekdayTodayResolvesToToday() {
        // Saying "thu" on a Thursday means today, not a week out.
        XCTAssertEqual(parse("quiz thu").dueAt, TestClock.date(2026, 9, 3))
    }

    func testNextWeekdaySkipsAWeek() {
        XCTAssertEqual(parse("test next thu").dueAt, TestClock.date(2026, 9, 10))
    }

    func testInNDays() {
        XCTAssertEqual(parse("project in 5 days").dueAt, TestClock.date(2026, 9, 8))
    }

    func testNumericDate() {
        XCTAssertEqual(parse("essay 9/18").dueAt, TestClock.date(2026, 9, 18))
    }

    func testNumericDateRollsToNextYearWhenPast() {
        XCTAssertEqual(parse("essay 1/5").dueAt, TestClock.date(2027, 1, 5))
    }

    func testMonthNameAndOrdinalDay() {
        XCTAssertEqual(parse("history paper oct 12th").dueAt, TestClock.date(2026, 10, 12))
    }

    func testNoDateLeavesDueNil() {
        let result = parse("bio lab report")
        XCTAssertNil(result.dueAt)
        XCTAssertFalse(result.matchedDate)
    }

    // MARK: - Times

    func testTimeAttachesToParsedDate() {
        let result = parse("essay due fri at 3pm")
        XCTAssertEqual(result.dueAt, TestClock.date(2026, 9, 4, 15, 0))
        XCTAssertTrue(result.hasDueTime)
    }

    func testTimeWithMinutes() {
        XCTAssertEqual(parse("quiz tomorrow 8:30am").dueAt, TestClock.date(2026, 9, 4, 8, 30))
    }

    func testTimeAloneMeansTodayWhenStillAhead() {
        XCTAssertEqual(parse("study session at 9pm").dueAt, TestClock.date(2026, 9, 3, 21, 0))
    }

    func testTimeAloneRollsToTomorrowWhenAlreadyPast() {
        // It is 4:00 PM in the test clock, so 8 AM has passed.
        XCTAssertEqual(parse("turn in form by 8am").dueAt, TestClock.date(2026, 9, 4, 8, 0))
    }

    func testBareNumberIsNotATime() {
        let result = parse("read chapter 7")
        XCTAssertNil(result.dueAt)
        XCTAssertEqual(result.title, "Read chapter 7")
    }

    // MARK: - Type, priority, duration

    func testTypeKeywords() {
        XCTAssertEqual(parse("bio test friday").type, .test)
        XCTAssertEqual(parse("alg quiz").type, .quiz)
        XCTAssertEqual(parse("eng essay").type, .essay)
        XCTAssertEqual(parse("read ch 3").type, .reading)
    }

    func testAbbreviationIsStrippedFromTitleAndFallsBackToTypeName() {
        let result = parse("bio hw tomorrow")
        XCTAssertEqual(result.type, .homework)
        XCTAssertEqual(result.title, "Homework")
    }

    func testPriorityFromBang() {
        XCTAssertEqual(parse("!! apush essay").priority, .high)
        XCTAssertEqual(parse("bio lab").priority, .normal)
    }

    func testTrailingBangIsStrippedFromTitle() {
        let result = parse("finish poster!!")
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.title, "Finish poster")
    }

    func testDurationJoinedAndSplit() {
        XCTAssertEqual(parse("bio lab 45m").estimatedMinutes, 45)
        XCTAssertEqual(parse("essay 2 hours").estimatedMinutes, 120)
    }

    // MARK: - Whole-line behavior

    func testKitchenSink() {
        let result = parse("!! world history essay due next tue at 11:59pm 90m")
        XCTAssertEqual(result.classID, "hist")
        XCTAssertEqual(result.title, "Essay")
        XCTAssertEqual(result.type, .essay)
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.estimatedMinutes, 90)
        XCTAssertEqual(result.dueAt, TestClock.date(2026, 9, 8, 23, 59))
        XCTAssertTrue(result.hasDueTime)
    }

    func testEmptyInput() {
        XCTAssertEqual(parse("   ").title, "")
    }

    func testFillerWordsAreTrimmedFromTitle() {
        XCTAssertEqual(parse("bio the frog diagram due tomorrow").title, "Frog diagram")
    }

    // MARK: - Clock parsing unit

    func testClockTimeParsing() {
        XCTAssertEqual(QuickAddParser.clockTime("3pm"), 15 * 60)
        XCTAssertEqual(QuickAddParser.clockTime("12am"), 0)
        XCTAssertEqual(QuickAddParser.clockTime("12pm"), 12 * 60)
        XCTAssertEqual(QuickAddParser.clockTime("11:59pm"), 23 * 60 + 59)
        XCTAssertEqual(QuickAddParser.clockTime("15:00"), 15 * 60)
        XCTAssertNil(QuickAddParser.clockTime("7"))
        XCTAssertNil(QuickAddParser.clockTime("banana"))
        XCTAssertNil(QuickAddParser.clockTime("25pm"))
    }
}
