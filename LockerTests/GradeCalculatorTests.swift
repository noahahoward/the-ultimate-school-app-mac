import XCTest
@testable import Locker

final class GradeCalculatorTests: XCTestCase {

    let tests = CategoryDef(id: "tests", name: "Tests", weight: 40)
    let homework = CategoryDef(id: "hw", name: "Homework", weight: 20)
    let finalExam = CategoryDef(id: "final", name: "Final", weight: 40)

    func testTotalPointsMode() {
        let items = [
            GradeItem(score: 18, maxScore: 20),
            GradeItem(score: 45, maxScore: 50),
        ]
        let percent = GradeCalculator.percent(items: items, categories: [], mode: .totalPoints)
        XCTAssertEqual(percent!, 63.0 / 70.0 * 100, accuracy: 0.001)
    }

    func testWeightedCategories() {
        let items = [
            GradeItem(score: 90, maxScore: 100, categoryID: "tests"),
            GradeItem(score: 100, maxScore: 100, categoryID: "hw"),
        ]
        // Tests 90% at weight 40, homework 100% at weight 20; the final has no
        // work yet so its weight drops out: (90*40 + 100*20) / 60.
        let percent = GradeCalculator.percent(items: items, categories: [tests, homework, finalExam], mode: .weightedCategories)
        XCTAssertEqual(percent!, (90 * 40 + 100 * 20) / 60.0, accuracy: 0.001)
    }

    func testUngradedCategoriesDoNotDragTheGradeDown() {
        let items = [GradeItem(score: 95, maxScore: 100, categoryID: "hw")]
        let percent = GradeCalculator.percent(items: items, categories: [tests, homework, finalExam], mode: .weightedCategories)
        XCTAssertEqual(percent!, 95, accuracy: 0.001)
    }

    func testNoGradedWorkReturnsNil() {
        XCTAssertNil(GradeCalculator.percent(items: [], categories: [tests], mode: .weightedCategories))
        XCTAssertNil(GradeCalculator.percent(items: [GradeItem(score: 0, maxScore: 0)], categories: [], mode: .totalPoints))
    }

    func testItemsInUnknownCategoriesFallBackToPoints() {
        let items = [GradeItem(score: 8, maxScore: 10, categoryID: "nope")]
        let percent = GradeCalculator.percent(items: items, categories: [tests], mode: .weightedCategories)
        XCTAssertEqual(percent!, 80, accuracy: 0.001)
    }

    func testBreakdownSumsPerCategory() {
        let items = [
            GradeItem(score: 8, maxScore: 10, categoryID: "hw"),
            GradeItem(score: 9, maxScore: 10, categoryID: "hw"),
            GradeItem(score: 40, maxScore: 50, categoryID: "tests"),
        ]
        let results = GradeCalculator.breakdown(items: items, categories: [tests, homework])
        XCTAssertEqual(results[0].percent!, 80, accuracy: 0.001)
        XCTAssertEqual(results[1].percent!, 85, accuracy: 0.001)
        XCTAssertEqual(results[1].itemCount, 2)
    }

    func testScoreNeededOnWeightedFinal() {
        // 88% carried into a final worth 20%, aiming for a 90.
        let needed = GradeCalculator.scoreNeeded(toReach: 90, currentPercent: 88, assessmentWeight: 20)
        XCTAssertEqual(needed!, (90 - 88 * 0.8) * 5, accuracy: 0.001)
        XCTAssertEqual(needed!, 98, accuracy: 0.001)
    }

    func testScoreNeededCanExceedOneHundred() {
        let needed = GradeCalculator.scoreNeeded(toReach: 95, currentPercent: 70, assessmentWeight: 20)
        XCTAssertGreaterThan(needed!, 100)
    }

    func testScoreNeededCanBeNegativeWhenAlreadySecured() {
        let needed = GradeCalculator.scoreNeeded(toReach: 60, currentPercent: 99, assessmentWeight: 10)
        XCTAssertLessThan(needed!, 0)
    }

    func testScoreNeededRequiresWeight() {
        XCTAssertNil(GradeCalculator.scoreNeeded(toReach: 90, currentPercent: 88, assessmentWeight: 0))
    }

    func testScoreNeededInPointsMode() {
        // 270/300 earned, a 100-point final, aiming for 90 overall.
        let needed = GradeCalculator.scoreNeeded(toReach: 90, earnedPoints: 270, possiblePoints: 300, upcomingPoints: 100)
        XCTAssertEqual(needed!, 90, accuracy: 0.001)
    }

    func testLetterGrades() {
        XCTAssertEqual(GradeCalculator.letter(for: 97), "A+")
        XCTAssertEqual(GradeCalculator.letter(for: 93), "A")
        XCTAssertEqual(GradeCalculator.letter(for: 89.9), "B+")
        XCTAssertEqual(GradeCalculator.letter(for: 0), "F")
    }

    func testGPA() {
        XCTAssertEqual(GradeCalculator.gpa(percents: [95, 85])!, 3.5, accuracy: 0.001)
        XCTAssertNil(GradeCalculator.gpa(percents: []))
    }
}
