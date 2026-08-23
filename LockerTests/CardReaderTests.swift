import XCTest
@testable import Locker

/// Built from a real Google Classroom dashboard: a sidebar list of enrolled
/// classes plus a grid of cards, each card holding a name, a period and a
/// teacher. Flattening that to text interleaves the cards, so it has to be read
/// from the geometry.
final class CardReaderTests: XCTestCase {

    /// Card columns on the real page sit 0.173 apart, so text has to be narrower
    /// than that — otherwise a long name would overlap the card beside it and the
    /// two would cluster together.
    func line(_ text: String, x: Double, y: Double) -> OCRLine {
        let width = min(0.155, max(0.02, 0.008 * Double(text.count)))
        return OCRLine(text: text, box: CGRect(x: x, y: y, width: width, height: 0.012))
    }

    /// Coordinates transcribed from the screenshot's OCR output.
    var classroomDashboard: OCRResult {
        OCRResult(lines: [
            // Browser and app furniture.
            line("Brave", x: 0.029, y: 0.983),
            line("Home - Classroom", x: 0.068, y: 0.950),
            line("Classroom", x: 0.065, y: 0.839),
            line("Home", x: 0.041, y: 0.783),
            line("Calendar", x: 0.041, y: 0.742),
            line("Classes", x: 0.235, y: 0.585),
            line("+ Add class", x: 0.860, y: 0.586),

            // Sidebar list of enrolled classes.
            line("FOUND HEALTH/FIT I-2-S1", x: 0.041, y: 0.570),
            line("2", x: 0.039, y: 0.555),
            line("AP HUMAN GEO I-8-S1", x: 0.041, y: 0.530),
            line("ALG 2 For Pre-Calc", x: 0.039, y: 0.488),
            line("Per 4 - Mrs. Barry", x: 0.040, y: 0.473),
            line("BIOLOGY 1-3-S1", x: 0.041, y: 0.447),

            // Card grid, first row.
            line("FOUND HEALTH/FITTA", x: 0.241, y: 0.528),
            line("AP HUMAN GEO I-8-S1", x: 0.416, y: 0.529),
            line("ALG 2 For Pre-Calc", x: 0.589, y: 0.529),
            line("BIOLOGY I-3-S1", x: 0.762, y: 0.529),
            line("2", x: 0.243, y: 0.506),
            line("8", x: 0.416, y: 0.506),
            line("Per 4 - Mrs. Barry", x: 0.588, y: 0.505),
            line("Zachary Myers", x: 0.243, y: 0.485),
            line("Todd Baker", x: 0.416, y: 0.487),
            line("Kate Barry", x: 0.589, y: 0.485),
            line("Benjamin Cook", x: 0.763, y: 0.485),
            line("Due Friday", x: 0.416, y: 0.452),
            line("Syllabus", x: 0.416, y: 0.438),

            // Card grid, second row.
            line("2026 Summer Homew...", x: 0.241, y: 0.264),
            line("Summer Homework A", x: 0.417, y: 0.264),
            line("Serena Sturgill", x: 0.243, y: 0.236),
            line("Todd Baker", x: 0.416, y: 0.237),

            // The assignment preview inside a card, which is not a class.
            line("Due Wednesday", x: 0.243, y: 0.186),
            line("Summer Homework", x: 0.243, y: 0.171),
            line("Assignment 2026", x: 0.243, y: 0.158),
        ])
    }

    var found: [ClassDraft] { CardReader.classes(from: classroomDashboard) }

    func testEveryEnrolledClassIsFound() {
        XCTAssertEqual(found.count, 6, "six classes are enrolled: \(found.map(\.name))")
    }

    func testPeriodsComeFromTheCards() {
        let periods = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.period) })
        XCTAssertEqual(periods["FOUND HEALTH/FIT I-2-S1"], 2)
        XCTAssertEqual(periods["BIOLOGY I-3-S1"], 3)
        XCTAssertEqual(periods["ALG 2 For Pre-Calc"], 4)
        XCTAssertEqual(periods["AP HUMAN GEO I-8-S1"], 8)
    }

    func testTeachersStayWithTheirOwnClass() {
        // Flattened text put Todd Baker against Biology; the geometry does not.
        let teachers = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.teacher) })
        XCTAssertEqual(teachers["BIOLOGY I-3-S1"], "Benjamin Cook")
        XCTAssertEqual(teachers["ALG 2 For Pre-Calc"], "Kate Barry")
        XCTAssertEqual(teachers["AP HUMAN GEO I-8-S1"], "Todd Baker")
    }

    func testSemesterIsReadFromTheCourseCode() {
        // "BIOLOGY I-3-S1" says period 3, semester 1 in its own name.
        let semesters = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.semester) })
        XCTAssertEqual(semesters["BIOLOGY I-3-S1"], 1)
        XCTAssertEqual(semesters["AP HUMAN GEO I-8-S1"], 1)
        XCTAssertEqual(semesters["ALG 2 For Pre-Calc"], 0, "no code, so it is not assumed to be one semester")
    }

    func testAnAssignmentPreviewIsNotImportedAsAClass() {
        // "Due Wednesday / Summer Homework / Assignment 2026" sits inside a card.
        XCTAssertFalse(found.contains { $0.name == "Assignment 2026" })
        XCTAssertFalse(found.contains { $0.name.hasPrefix("Due ") })
    }

    func testTheSidebarAndCardCopiesAreMergedKeepingTheFullerName() {
        // The card truncates to "FOUND HEALTH/FITTA"; the sidebar has it whole.
        let names = found.map(\.name)
        XCTAssertTrue(names.contains("FOUND HEALTH/FIT I-2-S1"))
        XCTAssertFalse(names.contains("FOUND HEALTH/FITTA"))
        let merged = found.first { $0.name == "FOUND HEALTH/FIT I-2-S1" }
        XCTAssertEqual(merged?.teacher, "Zachary Myers", "the teacher from the card survives the merge")
    }

    func testBrowserAndAppFurnitureIsIgnored() {
        let names = found.map(\.name)
        XCTAssertFalse(names.contains { $0.contains("Classroom") && $0.contains("Home") })
        XCTAssertFalse(names.contains("Calendar"))
        XCTAssertFalse(names.contains("+ Add class"))
    }

    // MARK: - Course codes

    func testPeriodAndSemesterAreReadFromACourseCode() {
        XCTAssertEqual(CardReader.periodInName("BIOLOGY I-3-S1"), 3)
        XCTAssertEqual(CardReader.semesterInName("BIOLOGY I-3-S1"), 1)
        XCTAssertEqual(CardReader.periodInName("FOUND HEALTH/FIT I-2-S1"), 2)
        XCTAssertEqual(CardReader.semesterInName("AP HUMAN GEO I-8-S2"), 2)
        XCTAssertNil(CardReader.periodInName("ALG 2 For Pre-Calc"))
    }

    func testAPageWithNoClassesYieldsNothing() {
        let ocr = OCRResult(lines: [
            line("Welcome back", x: 0.1, y: 0.9),
            line("You have no classes", x: 0.1, y: 0.8),
        ])
        XCTAssertTrue(CardReader.classes(from: ocr).isEmpty)
    }
}
