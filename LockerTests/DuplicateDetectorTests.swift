import XCTest
@testable import Locker

final class DuplicateDetectorTests: XCTestCase {

    let calendar = TestClock.calendar
    lazy var aug26 = TestClock.date(2026, 8, 26)
    lazy var sep2 = TestClock.date(2026, 9, 2)

    lazy var existing: [DuplicateDetector.AssignmentCandidate] = [
        .init(id: "a1", title: "Summer Homework Assignment 2026", classID: "eng", dueAt: aug26),
        .init(id: "a2", title: "Cell membrane diagram", classID: "bio", dueAt: sep2),
        .init(id: "a3", title: "Read chapters 4-5", classID: "eng", dueAt: nil),
    ]

    func find(_ title: String, classID: String? = nil, dueAt: Date? = nil) -> DuplicateDetector.Match? {
        DuplicateDetector.assignment(title: title, classID: classID, dueAt: dueAt,
                                     among: existing, calendar: calendar)
    }

    // MARK: - Assignments

    func testTheSameScreenshotImportedTwiceIsCaught() {
        let match = find("Summer Homework Assignment 2026", classID: "eng", dueAt: aug26)
        XCTAssertEqual(match?.id, "a1")
        XCTAssertEqual(match?.confidence, .certain)
    }

    func testPunctuationAndCaseDoNotHideADuplicate() {
        let match = find("summer homework: assignment 2026!", classID: "eng", dueAt: aug26)
        XCTAssertEqual(match?.id, "a1")
        XCTAssertEqual(match?.confidence, .certain)
    }

    func testSameTitleOnTheSameDayCountsEvenWithoutAClass() {
        let match = find("Summer Homework Assignment 2026", classID: nil, dueAt: aug26)
        XCTAssertEqual(match?.confidence, .certain)
    }

    func testSameTitleElsewhereIsOnlyPossible() {
        // Teachers reuse titles: "Reading log" in two classes is two tasks.
        let match = find("Summer Homework Assignment 2026", classID: "bio", dueAt: sep2)
        XCTAssertEqual(match?.confidence, .possible)
    }

    func testNearlyIdenticalWordingInTheSameClassIsFlagged() {
        let match = find("Cell membrane diagram worksheet", classID: "bio", dueAt: sep2)
        XCTAssertEqual(match?.id, "a2")
        XCTAssertEqual(match?.confidence, .possible)
    }

    func testGenuinelyDifferentWorkIsNotFlagged() {
        XCTAssertNil(find("Osmosis lab write-up", classID: "bio", dueAt: sep2))
        XCTAssertNil(find("Unit 2 test", classID: "eng", dueAt: aug26))
    }

    func testAnEmptyTitleMatchesNothing() {
        XCTAssertNil(find("", classID: "eng", dueAt: aug26))
        XCTAssertNil(find("   ", classID: "eng", dueAt: aug26))
    }

    func testNothingToCompareAgainst() {
        XCTAssertNil(DuplicateDetector.assignment(title: "Anything", classID: nil, dueAt: nil,
                                                  among: [], calendar: calendar))
    }

    // MARK: - Classes

    lazy var classes: [DuplicateDetector.ClassCandidate] = [
        .init(id: "c1", name: "BIOLOGY", semester: 1, period: 3),
        .init(id: "c2", name: "BIOLOGY", semester: 2, period: 3),
        .init(id: "c3", name: "Honors English 9", semester: 1, period: 6),
    ]

    func testReimportingTheSameScheduleFindsTheExistingClasses() {
        let match = DuplicateDetector.schoolClass(name: "BIOLOGY", semester: 1, period: 3, among: classes)
        XCTAssertEqual(match?.id, "c1")
        XCTAssertEqual(match?.confidence, .certain)
    }

    func testTheSameCourseInTheOtherSemesterIsNotADuplicate() {
        // Biology I and Biology II are two classes that share a name.
        let match = DuplicateDetector.schoolClass(name: "BIOLOGY", semester: 0, period: 3, among: classes)
        XCTAssertNil(match)
    }

    func testAShortenedNameIsFlaggedButNotAsCertain() {
        let match = DuplicateDetector.schoolClass(name: "Honors English", semester: 1, period: nil, among: classes)
        XCTAssertEqual(match?.id, "c3")
        XCTAssertEqual(match?.confidence, .possible)
    }

    func testAShortenedNameInTheSamePeriodIsCertain() {
        let match = DuplicateDetector.schoolClass(name: "Honors English", semester: 1, period: 6, among: classes)
        XCTAssertEqual(match?.confidence, .certain)
    }

    func testADifferentClassIsNotFlagged() {
        XCTAssertNil(DuplicateDetector.schoolClass(name: "Studio Art", semester: 1, period: 2, among: classes))
    }

    // MARK: - Comparison helpers

    func testTitleNormalization() {
        XCTAssertEqual(DuplicateDetector.normalize("Summer Homework: Assignment 2026!"),
                       "summer homework assignment 2026")
        XCTAssertEqual(DuplicateDetector.normalize("  spaced   out  "), "spaced out")
    }

    func testTokenOverlapIsRelativeToTheShorterTitle() {
        XCTAssertEqual(DuplicateDetector.tokenOverlap("cell membrane diagram",
                                                      "cell membrane diagram worksheet"), 1.0)
        XCTAssertEqual(DuplicateDetector.tokenOverlap("a b c d", "e f g h"), 0.0)
    }
}
