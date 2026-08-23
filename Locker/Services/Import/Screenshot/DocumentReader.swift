import Foundation
import AppKit
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

/// Turns a file into the same line-and-position text the screenshot reader works
/// with, so a PDF or a text file goes through exactly the same pipeline as an
/// image: label matching, then the model, then the table reader.
enum DocumentReader {

    enum Failure: LocalizedError {
        case unsupported(String)
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupported(let kind): "Locker can't read \(kind) files yet."
            case .unreadable: "That file couldn't be opened."
            case .empty: "No text was found in that file."
            }
        }
    }

    /// Everything the importer accepts, for the open panel and drop handling.
    static let readableTypes: [UTType] = [.png, .jpeg, .tiff, .heic, .image, .pdf, .plainText, .text, .commaSeparatedText]

    static func read(fileAt url: URL) throws -> OCRResult {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try readPDF(url)
        case "txt", "text", "md", "markdown", "csv", "tsv", "rtf":
            return try readPlainText(url)
        default:
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw Failure.unreadable
            }
            return try ScreenshotOCR.read(cgImage)
        }
    }

    // MARK: - PDF

    /// Pages are rendered and read visually rather than pulled from the text
    /// layer, because that keeps the column positions a schedule depends on and
    /// works the same on a scanned PDF as on a generated one.
    static func readPDF(_ url: URL) throws -> OCRResult {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw Failure.unreadable }

        let pageCount = min(document.pageCount, 10)
        var pages: [[OCRLine]] = []

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            guard let image = render(page) else { continue }
            guard let pageResult = try? ScreenshotOCR.read(image) else { continue }
            pages.append(pageResult.lines)
        }

        let lines = stack(pages)
        guard !lines.isEmpty else { throw Failure.empty }
        return OCRResult(lines: lines)
    }

    /// Lays pages out one above the next in a single coordinate space.
    ///
    /// Each page arrives already in reading order and is appended in that order,
    /// deliberately without a second global sort. Squeezing ten pages into one
    /// unit square puts neighbouring lines closer together than the sort's fixed
    /// threshold, and it would start reading across a page instead of down it.
    static func stack(_ pages: [[OCRLine]]) -> [OCRLine] {
        let filled = pages.filter { !$0.isEmpty }
        guard !filled.isEmpty else { return [] }

        let span = 1.0 / CGFloat(filled.count)
        return filled.enumerated().flatMap { index, page -> [OCRLine] in
            let offset = CGFloat(filled.count - 1 - index) * span
            return page.map { line in
                var moved = line
                moved.box = CGRect(
                    x: line.box.minX,
                    y: offset + line.box.minY * span,
                    width: line.box.width,
                    height: line.box.height * span
                )
                return moved
            }
        }
    }

    private static func render(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: - Plain text

    /// Text files have no layout, so each line is given a position that keeps its
    /// order. The pattern and model readers work on the text itself; the table
    /// reader will correctly decide there are no columns here.
    static func readPlainText(_ url: URL) throws -> OCRResult {
        let contents: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            contents = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            contents = latin
        } else {
            throw Failure.unreadable
        }
        return lines(fromText: contents)
    }

    static func lines(fromText text: String) -> OCRResult {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else { return OCRResult(lines: []) }

        let step = 1.0 / CGFloat(rows.count + 1)
        let lines = rows.enumerated().map { index, text in
            OCRLine(
                text: text,
                box: CGRect(
                    x: 0.05,
                    y: 1 - step * CGFloat(index + 1),
                    width: min(0.9, 0.01 * CGFloat(text.count)),
                    height: step * 0.6
                )
            )
        }
        return OCRResult(lines: lines)
    }
}
