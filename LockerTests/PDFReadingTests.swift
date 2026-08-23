import XCTest
@testable import Locker

/// A multi-page PDF is squeezed into one coordinate space. That used to put
/// lines closer together than the reading-order sort could tell apart, so it
/// began reading across a page instead of down it.
final class PDFReadingTests: XCTestCase {

    /// A page of many closely-spaced lines, as a dense syllabus produces.
    func page(_ prefix: String, lines count: Int) -> [OCRLine] {
        (0..<count).map { index in
            OCRLine(
                text: "\(prefix)-\(index)",
                box: CGRect(x: 0.08, y: 0.95 - Double(index) * (0.9 / Double(count)),
                            width: 0.4, height: 0.02)
            )
        }
    }

    func testPagesKeepTheirOrder() {
        let stacked = DocumentReader.stack([page("A", lines: 3), page("B", lines: 3)])
        XCTAssertEqual(stacked.map(\.text), ["A-0", "A-1", "A-2", "B-0", "B-1", "B-2"])
    }

    func testADenseTenPageDocumentStillReadsDownEachPage() {
        // Ten pages of thirty lines is where the old fixed threshold gave up:
        // the compressed gap between lines fell below it.
        let pages = (0..<10).map { page("P\($0)", lines: 30) }
        let stacked = DocumentReader.stack(pages)

        XCTAssertEqual(stacked.count, 300)
        XCTAssertEqual(stacked.first?.text, "P0-0")
        XCTAssertEqual(stacked.last?.text, "P9-29")

        // Every line must still follow the one above it on its own page.
        for pageIndex in 0..<10 {
            let texts = stacked.filter { $0.text.hasPrefix("P\(pageIndex)-") }.map(\.text)
            XCTAssertEqual(texts, (0..<30).map { "P\(pageIndex)-\($0)" },
                           "page \(pageIndex) was scrambled")
        }
    }

    func testPagesStayVerticallySeparated() {
        let stacked = DocumentReader.stack([page("A", lines: 5), page("B", lines: 5)])
        let lowestOnA = stacked.filter { $0.text.hasPrefix("A") }.map(\.box.midY).min() ?? 0
        let highestOnB = stacked.filter { $0.text.hasPrefix("B") }.map(\.box.midY).max() ?? 1
        XCTAssertGreaterThan(lowestOnA, highestOnB, "page one sits entirely above page two")
    }

    func testEmptyPagesAreSkipped() {
        let stacked = DocumentReader.stack([[], page("A", lines: 2), []])
        XCTAssertEqual(stacked.map(\.text), ["A-0", "A-1"])
    }

    func testNothingToStack() {
        XCTAssertTrue(DocumentReader.stack([]).isEmpty)
        XCTAssertTrue(DocumentReader.stack([[], []]).isEmpty)
    }
}
