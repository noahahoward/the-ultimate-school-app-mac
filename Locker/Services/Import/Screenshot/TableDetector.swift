import Foundation
import CoreGraphics

/// What a column of a schedule holds.
enum ColumnRole: String, CaseIterable, Identifiable, Sendable {
    case ignore, className, period, term, teacher, room, times, days

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ignore: "Ignore"
        case .className: "Class"
        case .period: "Period"
        case .term: "Term"
        case .teacher: "Teacher"
        case .room: "Room"
        case .times: "Times"
        case .days: "Days"
        }
    }
}

/// A schedule laid out as a grid, recovered from where the text sits on screen.
struct DetectedTable: Equatable, Sendable {
    /// Horizontal bands, left to right.
    var columns: [ClosedRange<CGFloat>] = []
    /// Cells, top row first. Every row has one entry per column.
    var rows: [[String]] = []

    var columnCount: Int { columns.count }
    var isUsable: Bool { columnCount >= 2 && rows.count >= 2 }

    func column(_ index: Int) -> [String] {
        rows.compactMap { index < $0.count ? $0[index] : nil }
    }
}

/// Rebuilds a table from OCR geometry.
///
/// Vision reports where every line sits, which is enough to recover rows and
/// columns without understanding a word. That matters because it works on any
/// Mac — Intel included — with no model, no download, and no guessing: the
/// layout is measured, not inferred.
enum TableDetector {

    /// Lines wider than this share of the image are treated as headings that span
    /// the table rather than as cells belonging to one column.
    private static let fullWidthShare: CGFloat = 0.7

    static func detect(_ lines: [OCRLine]) -> DetectedTable {
        let cells = lines.filter { $0.box.width < fullWidthShare }
        guard cells.count >= 4 else { return DetectedTable() }

        let columns = columnBands(cells)
        guard columns.count >= 2 else { return DetectedTable() }

        var table = DetectedTable(columns: columns)
        for row in rowGroups(cells) {
            var texts = [String](repeating: "", count: columns.count)
            for line in row {
                guard let index = columnIndex(for: line, in: columns) else { continue }
                texts[index] = texts[index].isEmpty
                    ? line.text
                    : texts[index] + " " + line.text
            }
            guard texts.contains(where: { !$0.isEmpty }) else { continue }
            table.rows.append(texts)
        }
        return table
    }

    /// Groups lines that sit at the same height into one row.
    static func rowGroups(_ lines: [OCRLine]) -> [[OCRLine]] {
        guard !lines.isEmpty else { return [] }
        let heights = lines.map(\.box.height).sorted()
        let median = heights[heights.count / 2]
        let tolerance = max(median * 0.6, 0.004)

        var groups: [[OCRLine]] = []
        var current: [OCRLine] = []
        var anchor: CGFloat = .infinity

        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if current.isEmpty || abs(line.box.midY - anchor) <= tolerance {
                if current.isEmpty { anchor = line.box.midY }
                current.append(line)
            } else {
                groups.append(current.sorted { $0.box.minX < $1.box.minX })
                current = [line]
                anchor = line.box.midY
            }
        }
        if !current.isEmpty { groups.append(current.sorted { $0.box.minX < $1.box.minX }) }
        return groups
    }

    /// Merges overlapping horizontal extents into column bands.
    static func columnBands(_ lines: [OCRLine]) -> [ClosedRange<CGFloat>] {
        let intervals = lines
            .map { $0.box.minX...max($0.box.minX, $0.box.maxX) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard !intervals.isEmpty else { return [] }

        var bands: [ClosedRange<CGFloat>] = []
        var lower = intervals[0].lowerBound
        var upper = intervals[0].upperBound

        for interval in intervals.dropFirst() {
            if interval.lowerBound <= upper {
                upper = max(upper, interval.upperBound)
            } else {
                bands.append(lower...upper)
                lower = interval.lowerBound
                upper = interval.upperBound
            }
        }
        bands.append(lower...upper)
        return bands
    }

    static func columnIndex(for line: OCRLine, in columns: [ClosedRange<CGFloat>]) -> Int? {
        let mid = line.box.midX
        if let exact = columns.firstIndex(where: { $0.contains(mid) }) { return exact }
        // A cell that straddles a band edge belongs to whichever band it overlaps most.
        return columns.indices.max { lhs, rhs in
            overlap(line.box, columns[lhs]) < overlap(line.box, columns[rhs])
        }
    }

    private static func overlap(_ box: CGRect, _ band: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(box.maxX, band.upperBound) - max(box.minX, band.lowerBound))
    }
}
