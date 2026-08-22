import Foundation
import Vision
import CoreGraphics
import AppKit

/// One line of text Vision found, with where it sat on screen.
struct OCRLine: Equatable {
    var text: String
    /// Normalized coordinates, origin bottom-left, as Vision reports them.
    var box: CGRect
}

struct OCRResult: Equatable {
    var lines: [OCRLine]

    /// The whole screenshot as text, in reading order. This is the only thing
    /// the model is ever shown, and the only thing an answer can be checked against.
    var text: String { lines.map(\.text).joined(separator: "\n") }

    var isEmpty: Bool { lines.isEmpty }
}

enum ScreenshotOCR {

    enum Failure: LocalizedError {
        case unreadableImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "That image couldn't be read."
            case .noTextFound: "No text was found in that screenshot."
            }
        }
    }

    /// Reads every line of text in an image.
    ///
    /// Language correction is deliberately off: screenshots contain exact strings
    /// like "APUSH" and "8/26", and autocorrecting them would defeat the point of
    /// checking the model's answers against this text.
    static func read(_ image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.unreadableImage
        }

        let observations = request.results ?? []
        let lines: [OCRLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, box: observation.boundingBox)
        }

        guard !lines.isEmpty else { throw Failure.noTextFound }
        return OCRResult(lines: readingOrder(lines))
    }

    static func read(_ image: NSImage) throws -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure.unreadableImage
        }
        return try read(cgImage)
    }

    /// Reading order, one column at a time.
    ///
    /// Sorting purely by height interleaves side-by-side panels: on a Google
    /// Classroom page the "Your work" sidebar lands in the middle of the title,
    /// splitting it in two. Lines are grouped into columns by horizontal overlap
    /// first, so each column is read top to bottom before moving right.
    static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let columns = columns(in: lines)
        guard columns.count > 1 else { return topToBottom(lines) }
        return columns.flatMap(topToBottom)
    }

    static func topToBottom(_ lines: [OCRLine]) -> [OCRLine] {
        lines.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > 0.006 { return lhs.box.midY > rhs.box.midY }
            return lhs.box.minX < rhs.box.minX
        }
    }

    /// Splits lines wherever a vertical gutter runs the full height of the image.
    /// A single-column screenshot yields one group and is left alone.
    static func columns(in lines: [OCRLine]) -> [[OCRLine]] {
        guard lines.count > 3 else { return [lines] }

        var groups: [[OCRLine]] = []
        var current: [OCRLine] = []
        var reach = -CGFloat.infinity

        for line in lines.sorted(by: { $0.box.minX < $1.box.minX }) {
            if current.isEmpty || line.box.minX <= reach {
                current.append(line)
                reach = max(reach, line.box.maxX)
            } else {
                groups.append(current)
                current = [line]
                reach = line.box.maxX
            }
        }
        if !current.isEmpty { groups.append(current) }

        // A "column" of one stray line is noise, not a layout.
        guard groups.count > 1, groups.allSatisfy({ $0.count >= 2 }) else { return [lines] }
        return groups
    }
}
