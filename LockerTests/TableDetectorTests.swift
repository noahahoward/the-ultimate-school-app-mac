import XCTest
@testable import Locker

/// The no-model path: recover a table from where the text sits, then work out
/// what each column holds. This runs on any Mac, Intel included.
final class TableDetectorTests: XCTestCase {

    /// Builds a grid of OCR lines at plausible coordinates. Cell widths follow
    /// the text, the way Vision reports them — a "1" is narrow, a course name
    /// is wide — because a fixed width would overlap neighbouring columns.
    func table(_ rows: [[String]], columnStarts: [Double]) -> [OCRLine] {
        var lines: [OCRLine] = []
        for (rowIndex, row) in rows.enumerated() {
            let y = 0.9 - Double(rowIndex) * 0.08
            for (columnIndex, text) in row.enumerated() where !text.isEmpty {
                let width = max(0.015, 0.012 * Double(text.count))
                lines.append(OCRLine(
                    text: text,
                    box: CGRect(x: columnStarts[columnIndex], y: y, width: width, height: 0.03)
                ))
            }
        }
        return lines
    }

    /// The layout the model mishandled: times first, no period column at all.
    var timesFirst: [OCRLine] {
        table([
            ["7:45-8:35 AM", "AP Biology", "Rm 204", "Alvarez, J", "M W F"],
            ["8:40-9:30 AM", "Honors Geometry", "Rm 118", "Chen, L", "M T W Th F"],
            ["9:35-10:25 AM", "World Literature", "Rm 232", "Patel, S", "T Th"],
            ["10:30-11:20 AM", "Studio Art", "Annex", "Boyd, R", "M W"],
        ], columnStarts: [0.04, 0.22, 0.44, 0.60, 0.80])
    }

    func testAGridIsRecoveredFromGeometry() {
        let detected = TableDetector.detect(timesFirst)
        XCTAssertEqual(detected.columnCount, 5)
        XCTAssertEqual(detected.rows.count, 4)
        XCTAssertTrue(detected.isUsable)
    }

    func testColumnsAreIdentifiedWithoutAModel() {
        let detected = TableDetector.detect(timesFirst)
        let roles = ColumnRoleGuesser.guess(for: detected)
        XCTAssertEqual(roles[0], .times)
        XCTAssertEqual(roles[1], .className)
        XCTAssertEqual(roles[2], .room)
        XCTAssertEqual(roles[3], .teacher)
        XCTAssertEqual(roles[4], .days)
    }

    func testClassesAreBuiltFromTheMappedTable() {
        let detected = TableDetector.detect(timesFirst)
        let roles = ColumnRoleGuesser.guess(for: detected)
        let rows = TableScheduleBuilder.rows(from: detected, roles: roles)

        XCTAssertEqual(rows.count, 4)
        let biology = rows[0]
        XCTAssertEqual(biology.name, "AP Biology")
        XCTAssertEqual(biology.room, "Rm 204")
        XCTAssertEqual(biology.teacher, "Alvarez, J")
        XCTAssertEqual(biology.startMinutes, 7 * 60 + 45)
        XCTAssertEqual(biology.endMinutes, 8 * 60 + 35)
        XCTAssertEqual(biology.weekdays, [2, 4, 6])
        // No period column exists, so none is invented.
        XCTAssertNil(biology.period)
    }

    /// The other layout the model mishandled: bare columns, no labels.
    var unlabelledColumns: [OCRLine] {
        table([
            ["1", "ENGLISH 9", "210", "SMITH, J", "FULL YEAR"],
            ["2", "ALGEBRA I", "118", "OKAFOR, D", "FULL YEAR"],
            ["3", "PHYSICAL SCIENCE", "305", "REYES, M", "FULL YEAR"],
            ["4", "WORLD GEOGRAPHY", "150", "DUNN, T", "SEMESTER 1"],
        ], columnStarts: [0.04, 0.14, 0.42, 0.56, 0.76])
    }

    func testABareNumberColumnIsReadAsPeriodsAndARoomColumnIsNot() {
        let detected = TableDetector.detect(unlabelledColumns)
        let roles = ColumnRoleGuesser.guess(for: detected)
        XCTAssertEqual(roles[0], .period, "1-4 are periods")
        XCTAssertEqual(roles[2], .room, "210-305 are too large to be periods")
        XCTAssertEqual(roles[3], .teacher)
        XCTAssertEqual(roles[4], .term)
        XCTAssertEqual(roles[1], .className)
    }

    func testTermsAndPeriodsSurviveIntoTheClasses() {
        let detected = TableDetector.detect(unlabelledColumns)
        let roles = ColumnRoleGuesser.guess(for: detected)
        let rows = TableScheduleBuilder.rows(from: detected, roles: roles)

        XCTAssertEqual(rows.map(\.name), ["ENGLISH 9", "ALGEBRA I", "PHYSICAL SCIENCE", "WORLD GEOGRAPHY"])
        XCTAssertEqual(rows.map(\.period), [1, 2, 3, 4])
        XCTAssertEqual(rows.map(\.semester), [0, 0, 0, 1])
        XCTAssertEqual(rows[0].room, "210")
    }

    // MARK: - Guards

    func testAHeaderRowIsNotImportedAsAClass() {
        let lines = table([
            ["Period", "Course", "Room"],
            ["1", "ENGLISH 9", "210"],
            ["2", "ALGEBRA I", "118"],
        ], columnStarts: [0.04, 0.16, 0.44])
        let detected = TableDetector.detect(lines)
        let roles = ColumnRoleGuesser.guess(for: detected)
        let rows = TableScheduleBuilder.rows(from: detected, roles: roles)
        XCTAssertFalse(rows.contains { $0.name.lowercased() == "course" })
    }

    func testTooLittleTextIsNotATable() {
        let lines = [OCRLine(text: "Welcome", box: CGRect(x: 0.1, y: 0.9, width: 0.2, height: 0.03))]
        XCTAssertFalse(TableDetector.detect(lines).isUsable)
    }

    func testAFullWidthHeadingIsNotTreatedAsACell() {
        var lines = timesFirst
        lines.append(OCRLine(text: "Student Schedule 2026-2027",
                             box: CGRect(x: 0.04, y: 0.97, width: 0.9, height: 0.04)))
        let detected = TableDetector.detect(lines)
        // The banner spans every column, so folding it in would merge them all.
        XCTAssertEqual(detected.columnCount, 5)
    }

    func testNoClassColumnMeansNoClasses() {
        let detected = TableDetector.detect(timesFirst)
        let roles = [ColumnRole](repeating: .ignore, count: detected.columnCount)
        XCTAssertTrue(TableScheduleBuilder.rows(from: detected, roles: roles).isEmpty)
    }

    // MARK: - Content tests used by the guesser

    func testNameDetection() {
        XCTAssertTrue(ColumnRoleGuesser.looksLikeAName("SMITH, J"))
        XCTAssertTrue(ColumnRoleGuesser.looksLikeAName("Mrs. Sturgill"))
        XCTAssertFalse(ColumnRoleGuesser.looksLikeAName("204"))
        // Two capitalised words describes most course names as well as most
        // people, so it cannot decide a column on its own.
        XCTAssertFalse(ColumnRoleGuesser.looksLikeAName("AP Biology"))
        XCTAssertFalse(ColumnRoleGuesser.looksLikeAName("Physical Science"))
        XCTAssertFalse(ColumnRoleGuesser.looksLikeAName("Serena Sturgill"))
    }

    func testATeacherColumnIsNotReadAsMeetingDays() {
        // "SMITH, J" contains an m and a t, which a loose day parser reads as
        // Monday and Tuesday.
        XCTAssertFalse(ColumnRoleGuesser.matches("SMITH, J", role: .days))
        XCTAssertFalse(ColumnRoleGuesser.matches("DUNN, T", role: .days))
        XCTAssertTrue(ColumnRoleGuesser.matches("M W F", role: .days))
        XCTAssertTrue(ColumnRoleGuesser.matches("Mon/Wed/Fri", role: .days))
    }

    func testRoomsAreDistinguishedFromPeriods() {
        XCTAssertTrue(ColumnRoleGuesser.matches("210", role: .room))
        XCTAssertTrue(ColumnRoleGuesser.matches("Rm 118", role: .room))
        XCTAssertFalse(ColumnRoleGuesser.matches("3", role: .room), "3 is a period, not a room")
        XCTAssertTrue(ColumnRoleGuesser.matches("3", role: .period))
    }
}
