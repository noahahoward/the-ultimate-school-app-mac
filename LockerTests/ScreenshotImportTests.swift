import XCTest
@testable import Locker

/// Built around a real Google Classroom assignment screenshot, transcribed the way
/// Vision reads it: top to bottom, columns joined per row.
final class ScreenshotImportTests: XCTestCase {

    let calendar = TestClock.calendar
    /// Taken in late August, which is what makes "Jun 17" a backward-looking date.
    lazy var now = TestClock.date(2026, 8, 22, 12, 0)

    let ocrText = """
    Summer Homework Assignment 2026
    Your work
    Assigned
    Serena Sturgill • Jun 17
    NOAH HOWAR...
    Google Docs
    4 points | Due Aug 26
    Add or create
    !2026 Summer Home...
    Google Docs
    Originality reports
    Run
    Class comments
    Add comment
    Turn in
    Private comments
    Add comment to Serena Sturgill
    """

    /// What the model is expected to return for that screenshot.
    var honestFields: ExtractedFields {
        var fields = ExtractedFields()
        fields.title = "Summer Homework Assignment 2026"
        fields.teacher = "Serena Sturgill"
        fields.dueDateText = "Due Aug 26"
        fields.assignedDateText = "Jun 17"
        fields.pointsText = "4 points"
        fields.statusText = "Assigned"
        fields.attachments = ["!2026 Summer Home..."]
        fields.summary = "Complete the summer homework document and turn it in."
        return fields
    }

    // MARK: - Evidence

    func testHonestFieldsAllSurvive() {
        let outcome = EvidenceCheck.verify(honestFields, against: ocrText)
        XCTAssertTrue(outcome.rejected.isEmpty, "unexpected rejections: \(outcome.rejected)")
        XCTAssertEqual(outcome.fields.title, "Summer Homework Assignment 2026")
        XCTAssertEqual(outcome.fields.pointsText, "4 points")
        XCTAssertEqual(outcome.fields.attachments, ["!2026 Summer Home..."])
    }

    func testAnInventedDueDateIsThrownAway() {
        var lying = honestFields
        lying.dueDateText = "Sep 15"

        let outcome = EvidenceCheck.verify(lying, against: ocrText)
        XCTAssertEqual(outcome.fields.dueDateText, "", "a date that isn't on screen must not survive")
        XCTAssertEqual(outcome.rejected.map(\.name), ["Due date"])
    }

    func testAnInventedClassNameIsThrownAway() {
        var lying = honestFields
        lying.className = "AP Biology"
        let outcome = EvidenceCheck.verify(lying, against: ocrText)
        XCTAssertEqual(outcome.fields.className, "")
        XCTAssertEqual(outcome.rejected.first?.name, "Class")
    }

    func testAPlausibleButWrongPointsValueIsThrownAway() {
        var lying = honestFields
        lying.pointsText = "40 points"
        let outcome = EvidenceCheck.verify(lying, against: ocrText)
        XCTAssertEqual(outcome.fields.pointsText, "")
    }

    func testTruncatedLabelsStillCount() {
        // "!2026 Summer Home..." is genuinely on screen, ellipsis and all.
        XCTAssertTrue(EvidenceCheck.isSupported("!2026 Summer Home...", by: EvidenceCheck.normalize(ocrText)))
    }

    func testSummaryIsNotRequiredToAppearOnScreen() {
        let outcome = EvidenceCheck.verify(honestFields, against: ocrText)
        XCTAssertEqual(outcome.fields.summary, "Complete the summer homework document and turn it in.")
    }

    func testEmptySlotsAreNotRejections() {
        let outcome = EvidenceCheck.verify(ExtractedFields(), against: ocrText)
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    // MARK: - Dates

    func testDueDateParsing() {
        XCTAssertEqual(FieldParsing.date(from: "Due Aug 26", now: now, calendar: calendar), TestClock.date(2026, 8, 26))
        XCTAssertEqual(FieldParsing.date(from: "Aug 26", now: now, calendar: calendar), TestClock.date(2026, 8, 26))
        XCTAssertEqual(FieldParsing.date(from: "August 26th", now: now, calendar: calendar), TestClock.date(2026, 8, 26))
        XCTAssertEqual(FieldParsing.date(from: "8/26", now: now, calendar: calendar), TestClock.date(2026, 8, 26))
        XCTAssertEqual(FieldParsing.date(from: "Aug 26, 2027", now: now, calendar: calendar), TestClock.date(2027, 8, 26))
    }

    func testARecentlyPassedDateStaysInTheSameYear() {
        // Posted "Jun 17" on a screenshot taken in August means this June, not next.
        XCTAssertEqual(FieldParsing.date(from: "Jun 17", now: now, calendar: calendar), TestClock.date(2026, 6, 17))
    }

    func testADistantPastDateRollsForward() {
        // "Jan 5" in late August is closer to next January than the one gone by.
        XCTAssertEqual(FieldParsing.date(from: "Jan 5", now: now, calendar: calendar), TestClock.date(2027, 1, 5))
    }

    func testUnparseableDatesReturnNil() {
        XCTAssertNil(FieldParsing.date(from: "", now: now, calendar: calendar))
        XCTAssertNil(FieldParsing.date(from: "sometime next week", now: now, calendar: calendar))
        XCTAssertNil(FieldParsing.date(from: "Turn in", now: now, calendar: calendar))
    }

    // MARK: - Points and status

    func testPointsParsing() {
        XCTAssertEqual(FieldParsing.points(from: "4 points"), 4)
        XCTAssertEqual(FieldParsing.points(from: "100 pts"), 100)
        XCTAssertEqual(FieldParsing.points(from: "12.5 points"), 12.5)
        XCTAssertNil(FieldParsing.points(from: "Ungraded"))
        XCTAssertNil(FieldParsing.points(from: ""))
    }

    func testStatusParsing() {
        XCTAssertEqual(FieldParsing.isTurnedIn(from: "Assigned"), false)
        XCTAssertEqual(FieldParsing.isTurnedIn(from: "Turned in"), true)
        XCTAssertEqual(FieldParsing.isTurnedIn(from: "Missing"), false)
        XCTAssertEqual(FieldParsing.isTurnedIn(from: "Returned"), true)
        // Anything unfamiliar leaves the assignment's state alone.
        XCTAssertNil(FieldParsing.isTurnedIn(from: "Graded"))
        XCTAssertNil(FieldParsing.isTurnedIn(from: ""))
    }

    // MARK: - The whole screenshot

    func testDraftFromTheRealScreenshot() {
        let outcome = EvidenceCheck.verify(honestFields, against: ocrText)
        let draft = FieldParsing.draft(from: outcome.fields, rejected: outcome.rejected, now: now, calendar: calendar)

        XCTAssertEqual(draft.title, "Summer Homework Assignment 2026")
        XCTAssertEqual(draft.teacher, "Serena Sturgill")
        XCTAssertEqual(draft.dueAt, TestClock.date(2026, 8, 26))
        XCTAssertEqual(draft.assignedAt, TestClock.date(2026, 6, 17))
        XCTAssertEqual(draft.maxPoints, 4)
        XCTAssertEqual(draft.isTurnedIn, false)
        XCTAssertEqual(draft.attachments, ["!2026 Summer Home..."])
        XCTAssertEqual(draft.type, .homework)
        XCTAssertTrue(draft.isUsable)
        XCTAssertTrue(draft.rejected.isEmpty)
    }

    func testADraftWithAnInventedDateKeepsEverythingElseAndReportsTheRejection() {
        var lying = honestFields
        lying.dueDateText = "Sep 30"
        let outcome = EvidenceCheck.verify(lying, against: ocrText)
        let draft = FieldParsing.draft(from: outcome.fields, rejected: outcome.rejected, now: now, calendar: calendar)

        XCTAssertNil(draft.dueAt, "an unverifiable due date must not reach the draft")
        XCTAssertEqual(draft.title, "Summer Homework Assignment 2026")
        XCTAssertEqual(draft.maxPoints, 4)
        XCTAssertEqual(draft.rejected.count, 1)
    }

    func testADraftWithNoTitleIsNotUsable() {
        XCTAssertFalse(ImportDraft().isUsable)
    }

    // MARK: - OCR ordering

    func testReadingOrderIsTopDownThenLeftRight() {
        let lines = [
            OCRLine(text: "Due Aug 26", box: CGRect(x: 0.4, y: 0.80, width: 0.2, height: 0.03)),
            OCRLine(text: "Title", box: CGRect(x: 0.1, y: 0.95, width: 0.3, height: 0.04)),
            OCRLine(text: "4 points", box: CGRect(x: 0.1, y: 0.801, width: 0.1, height: 0.03)),
        ]
        XCTAssertEqual(ScreenshotOCR.readingOrder(lines).map(\.text), ["Title", "4 points", "Due Aug 26"])
    }
}

/// Regression tests for the things a real Google Classroom screenshot exposed.
final class ScreenshotLayoutTests: XCTestCase {

    /// Geometry matching the real screenshot: a wide left column with the title
    /// split across two lines, and a narrow "Your work" panel on the right whose
    /// lines sit between them vertically.
    var twoColumnPage: [OCRLine] {
        [
            OCRLine(text: "Summer Homework", box: CGRect(x: 0.08, y: 0.94, width: 0.40, height: 0.04)),
            OCRLine(text: "Your work", box: CGRect(x: 0.65, y: 0.93, width: 0.15, height: 0.03)),
            OCRLine(text: "Assigned", box: CGRect(x: 0.85, y: 0.93, width: 0.10, height: 0.03)),
            OCRLine(text: "Assignment 2026", box: CGRect(x: 0.08, y: 0.89, width: 0.38, height: 0.04)),
            OCRLine(text: "Serena Sturgill • Jun 17", box: CGRect(x: 0.08, y: 0.80, width: 0.25, height: 0.03)),
            OCRLine(text: "4 points | Due Aug 26", box: CGRect(x: 0.08, y: 0.75, width: 0.25, height: 0.03)),
            OCRLine(text: "Turn in", box: CGRect(x: 0.70, y: 0.35, width: 0.20, height: 0.04)),
        ]
    }

    func testColumnsAreReadOneAtATime() {
        let ordered = ScreenshotOCR.readingOrder(twoColumnPage).map(\.text)
        // The title's two halves must end up adjacent, not split by the side panel.
        let first = ordered.firstIndex(of: "Summer Homework")!
        let second = ordered.firstIndex(of: "Assignment 2026")!
        XCTAssertEqual(second, first + 1, "the sidebar split the title: \(ordered)")
    }

    func testSingleColumnPagesAreLeftAlone() {
        let lines = [
            OCRLine(text: "Bottom", box: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.03)),
            OCRLine(text: "Top", box: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.03)),
            OCRLine(text: "Middle", box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.03)),
            OCRLine(text: "Lower", box: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.03)),
        ]
        XCTAssertEqual(ScreenshotOCR.readingOrder(lines).map(\.text), ["Top", "Middle", "Lower", "Bottom"])
    }

    // MARK: - Slot cleanup

    func testAMultiLineTitleIsCollapsedToOneLine() {
        var fields = ExtractedFields()
        fields.title = "Summer Homework\nAssignment 2026"
        let outcome = EvidenceCheck.verify(fields, against: "Summer Homework\nAssignment 2026\n4 points")
        XCTAssertEqual(outcome.fields.title, "Summer Homework Assignment 2026")
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    func testFileTypeLabelsAreNotTreatedAsAttachmentNames() {
        var fields = ExtractedFields()
        fields.attachments = ["Google Docs", "Google Docs", "!2026 Summer Home..."]
        let ocr = "!2026 Summer Home...\nGoogle Docs\nGoogle Docs"
        let outcome = EvidenceCheck.verify(fields, against: ocr)
        XCTAssertEqual(outcome.fields.attachments, ["!2026 Summer Home..."])
    }

    func testDuplicateAttachmentsAreCollapsed() {
        var fields = ExtractedFields()
        fields.attachments = ["Unit 3 packet", "Unit 3 packet"]
        let outcome = EvidenceCheck.verify(fields, against: "Unit 3 packet")
        XCTAssertEqual(outcome.fields.attachments, ["Unit 3 packet"])
    }

    func testASummaryThatIsJustAButtonIsDropped() {
        var fields = ExtractedFields()
        fields.summary = "Add comment"
        let outcome = EvidenceCheck.verify(fields, against: "Add comment")
        XCTAssertEqual(outcome.fields.summary, "")
    }

    func testARealSummaryIsKept() {
        var fields = ExtractedFields()
        fields.summary = "Read the packet and answer the questions."
        let outcome = EvidenceCheck.verify(fields, against: "anything")
        XCTAssertEqual(outcome.fields.summary, "Read the packet and answer the questions.")
    }
}
