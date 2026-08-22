import Foundation

/// Fills the slots without a model, by looking for the labels school software
/// actually prints: "Due ...", "N points", "Assigned", "Turned in".
///
/// This is the floor the feature stands on. It runs on any Mac, needs nothing
/// downloaded or enabled, and on a tidy Google Classroom page it gets most of it.
/// The model's job is to do better than this on messier layouts, not to replace it.
enum HeuristicExtractor {

    private static let statusWords = [
        "turned in", "handed in", "submitted", "returned",
        "assigned", "missing", "not turned in", "no submission",
    ]

    static func extract(from ocr: OCRResult) -> ExtractedFields {
        var fields = ExtractedFields()
        let lines = ocr.lines.map(\.text)
        guard !lines.isEmpty else { return fields }

        // The title is the first line that isn't obviously chrome.
        fields.title = lines.first { !isChrome($0) } ?? lines[0]

        for line in lines {
            let lower = line.lowercased()

            if fields.dueDateText.isEmpty, let due = segment(of: line, containing: "due") {
                fields.dueDateText = due
            }
            if fields.pointsText.isEmpty,
               lower.contains("point") || lower.contains(" pts") || lower.hasSuffix("pts"),
               let points = segment(of: line, containing: "point") ?? segment(of: line, containing: "pts") {
                fields.pointsText = points
            }
            if fields.statusText.isEmpty, let status = statusWords.first(where: { lower == $0 }) {
                // Preserve the original capitalization rather than the match.
                fields.statusText = line.trimmingCharacters(in: .whitespaces)
                _ = status
            }
            // "Serena Sturgill • Jun 17" — a byline with a date after a bullet.
            if fields.assignedDateText.isEmpty, line.contains("•") {
                let parts = line.split(separator: "•").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    if fields.teacher.isEmpty, !parts[0].isEmpty, !isChrome(parts[0]) { fields.teacher = parts[0] }
                    if FieldParsing.date(from: parts[1]) != nil { fields.assignedDateText = parts[1] }
                }
            }
        }
        return fields
    }

    /// Pulls the run of text around a keyword, split on the column separators
    /// screenshots use, so "4 points | Due Aug 26" yields each half on its own.
    static func segment(of line: String, containing keyword: String) -> String? {
        let pieces = line
            .split(whereSeparator: { $0 == "|" || $0 == "·" || $0 == "•" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return pieces.first { $0.lowercased().contains(keyword) }
    }

    static func isChrome(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        let chrome = [
            "your work", "class comments", "private comments", "add comment",
            "add or create", "originality reports", "run", "turn in", "google docs",
            "mark as done", "assigned", "due", "points",
        ]
        return chrome.contains(lower) || lower.isEmpty
    }
}
