import XCTest
@testable import Locker

final class ClassMatcherTests: XCTestCase {

    let biology = ClassMatcher.Candidate(id: "bio", name: "Biology I", teacher: "Mrs. Sturgill", aliases: ["bio"])
    let algebra = ClassMatcher.Candidate(id: "alg", name: "Algebra 2", teacher: "Mr. Okafor", aliases: ["alg", "math"])
    let english = ClassMatcher.Candidate(id: "eng", name: "English 9", teacher: "")

    var classes: [ClassMatcher.Candidate] { [biology, algebra, english] }

    func match(className: String = "", teacher: String = "") -> ClassMatcher.Match {
        ClassMatcher.match(className: className, teacher: teacher, in: classes)
    }

    // MARK: - By name

    func testClassNameWins() {
        XCTAssertEqual(match(className: "Biology I", teacher: "Mr. Okafor"),
                       .matched(id: "bio", reason: .className))
    }

    func testNicknameMatches() {
        // "math" is nothing like "Algebra 2", so only the alias list can find it.
        XCTAssertEqual(match(className: "math"), .matched(id: "alg", reason: .alias))
    }

    func testAShortenedClassNameStillMatchesTheCourse() {
        XCTAssertEqual(match(className: "alg"), .matched(id: "alg", reason: .className))
    }

    // MARK: - By teacher

    func testTeacherMatchesAcrossDifferentFormsOfTheName() {
        // The screenshot says "Serena Sturgill"; the class says "Mrs. Sturgill".
        XCTAssertEqual(match(teacher: "Serena Sturgill"), .matched(id: "bio", reason: .teacher))
    }

    func testTeacherMatchIsCaseAndTitleInsensitive() {
        XCTAssertEqual(match(teacher: "STURGILL"), .matched(id: "bio", reason: .teacher))
        XCTAssertEqual(match(teacher: "Ms. Sturgill"), .matched(id: "bio", reason: .teacher))
        XCTAssertEqual(match(teacher: "sturgill, serena"), .matched(id: "bio", reason: .teacher))
    }

    func testUnknownTeacherMatchesNothing() {
        XCTAssertEqual(match(teacher: "Mr. Nobody"), .none)
    }

    func testClassesWithNoTeacherRecordedAreNotMatched() {
        XCTAssertEqual(match(teacher: "English"), .none)
    }

    // MARK: - Refusing to guess

    func testATeacherWithTwoOfYourClassesIsAmbiguousRatherThanWrong() {
        let candidates = [
            ClassMatcher.Candidate(id: "bio", name: "Biology I", teacher: "Mrs. Sturgill"),
            ClassMatcher.Candidate(id: "chem", name: "Chemistry", teacher: "Serena Sturgill"),
        ]
        let result = ClassMatcher.match(className: "", teacher: "Sturgill", in: candidates)
        XCTAssertEqual(result, .ambiguous(ids: ["bio", "chem"], reason: .teacher))
        XCTAssertNil(result.id, "an ambiguous match must not select a class")
    }

    func testNothingToMatchAgainst() {
        XCTAssertEqual(ClassMatcher.match(className: "Biology", teacher: "Sturgill", in: []), .none)
        XCTAssertEqual(match(), .none)
    }

    // MARK: - Surnames

    func testSurnameExtraction() {
        XCTAssertEqual(ClassMatcher.surname(of: "Mrs. Sturgill"), "sturgill")
        XCTAssertEqual(ClassMatcher.surname(of: "Serena Sturgill"), "sturgill")
        XCTAssertEqual(ClassMatcher.surname(of: "Dr. Maria Van Der Berg"), "berg")
        XCTAssertEqual(ClassMatcher.surname(of: "Coach Bell"), "bell")
        XCTAssertEqual(ClassMatcher.surname(of: "O'Brien"), "o'brien")
        // Gradebooks list people surname-first.
        XCTAssertEqual(ClassMatcher.surname(of: "Sturgill, Serena"), "sturgill")
        XCTAssertEqual(ClassMatcher.surname(of: "Okafor, Daniel J."), "okafor")
        XCTAssertNil(ClassMatcher.surname(of: ""))
        XCTAssertNil(ClassMatcher.surname(of: "Mr."), "a title alone names nobody")
    }

    // MARK: - The same subject under a longer name

    private var twoTerms: [ClassMatcher.Candidate] {
        [
            .init(id: "eng1", name: "HONORS ENGLISH 9 I", teacher: "Dana Whitlock", semester: 1),
            .init(id: "eng2", name: "HONORS ENGLISH 9 II", teacher: "Dana Whitlock", semester: 2),
            .init(id: "bio1", name: "BIOLOGY I", teacher: "Ray Alderton", semester: 1),
            .init(id: "hf1", name: "FOUND HEALTH/FIT I", teacher: "Ray Alderton", semester: 1),
        ]
    }

    func testCoursePageNameWrappedAroundTheSubjectStillMatches() {
        let match = ClassMatcher.match(className: "2026 Summer Homework: Honors ELA 9",
                                       teacher: "", in: twoTerms, semesterInForce: 1)
        XCTAssertEqual(match, .matched(id: "eng1", reason: .subject))
    }

    func testTheSemesterRunningPicksBetweenTheTwoHalvesOfACourse() {
        // The name alone fits both halves; the running semester settles it.
        let match = ClassMatcher.match(className: "Honors English 9",
                                       teacher: "", in: twoTerms, semesterInForce: 2)
        XCTAssertEqual(match, .matched(id: "eng2", reason: .className))
    }

    func testAYearGroupIsNotDroppedAsNoise() {
        XCTAssertFalse(ClassMatcher.sameSubject(ClassMatcher.subjectWords(in: "ENGLISH 9"),
                                                ClassMatcher.subjectWords(in: "ENGLISH 10")))
    }

    func testWithoutASemesterBothHalvesStayTheStudentsCall() {
        let match = ClassMatcher.match(className: "Honors English 9", teacher: "", in: twoTerms)
        guard case .ambiguous(let ids, _) = match else { return XCTFail("expected a tie") }
        XCTAssertEqual(Set(ids), ["eng1", "eng2"])
    }

    func testOneWordInCommonIsNotASubject() {
        let match = ClassMatcher.match(className: "Health", teacher: "", in: twoTerms,
                                       semesterInForce: 1)
        XCTAssertEqual(match, .none)
    }

    func testADifferentSubjectDoesNotMatch() {
        let match = ClassMatcher.match(className: "Summer Homework AP Human Geo 2026",
                                       teacher: "", in: twoTerms, semesterInForce: 1)
        XCTAssertEqual(match, .none)
    }

    func testAFullNameStillBeatsTheSubject() {
        let match = ClassMatcher.match(className: "BIOLOGY I", teacher: "", in: twoTerms,
                                       semesterInForce: 1)
        XCTAssertEqual(match, .matched(id: "bio1", reason: .className))
    }

    func testSubjectWordsDropTheYearAndThePageDescription() {
        XCTAssertEqual(ClassMatcher.subjectWords(in: "2026 Summer Homework: Honors ELA 9"),
                       ["honors", "english", "9"])
        XCTAssertEqual(ClassMatcher.subjectWords(in: "AP HUMAN GEO I-8-S1"),
                       ["ap", "human", "geography", "8"])
    }

    func testNumbersAgreeingIsNotASubject() {
        XCTAssertFalse(ClassMatcher.sameSubject(["9", "2"], ["9", "2", "spanish"]))
    }
}
