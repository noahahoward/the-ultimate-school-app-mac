import XCTest
@testable import Locker

/// Files go through the same reader as screenshots, so a schedule pasted into a
/// text file imports the same way a picture of one does.
final class DocumentReaderTests: XCTestCase {

    func testPlainTextBecomesOrderedLines() {
        let result = DocumentReader.lines(fromText: """
            SPANISH 2
            Period 1 - SEMESTER 1
            BIOLOGY
            Period 3 - SEMESTER 1
            """)
        XCTAssertEqual(result.lines.map(\.text),
                       ["SPANISH 2", "Period 1 - SEMESTER 1", "BIOLOGY", "Period 3 - SEMESTER 1"])
    }

    func testBlankLinesAreDropped() {
        let result = DocumentReader.lines(fromText: "First\n\n   \nSecond\n")
        XCTAssertEqual(result.lines.map(\.text), ["First", "Second"])
    }

    func testLinesKeepTopToBottomOrder() {
        let result = DocumentReader.lines(fromText: "Top\nMiddle\nBottom")
        let ys = result.lines.map(\.box.midY)
        XCTAssertEqual(ys, ys.sorted(by: >), "earlier lines must sit higher")
    }

    func testATextScheduleParsesLikeAScreenshotOfOne() {
        let result = DocumentReader.lines(fromText: """
            SPANISH 2 I
            Period 1 - SEMESTER 1
            BIOLOGY I
            Period 3 - SEMESTER 1
            ENGINEERING CAD
            Period 8 - SEMESTER 2
            """)
        let rows = ScheduleParsing.rows(from: result)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.period), [1, 3, 8])
        XCTAssertEqual(rows.map(\.semester), [1, 1, 2])
    }

    func testEmptyTextYieldsNothing() {
        XCTAssertTrue(DocumentReader.lines(fromText: "").lines.isEmpty)
        XCTAssertTrue(DocumentReader.lines(fromText: "\n\n  \n").lines.isEmpty)
    }

    func testAnUnreadableFileReportsItself() {
        let missing = URL(fileURLWithPath: "/tmp/locker-does-not-exist-\(UUID().uuidString).pdf")
        XCTAssertThrowsError(try DocumentReader.read(fileAt: missing))
    }

    func testTheOpenPanelAcceptsDocumentsAsWellAsImages() {
        let names = DocumentReader.readableTypes.map(\.identifier)
        XCTAssertTrue(names.contains { $0.contains("pdf") })
        XCTAssertTrue(names.contains { $0.contains("text") })
        XCTAssertTrue(names.contains { $0.contains("image") || $0.contains("png") })
    }
}
