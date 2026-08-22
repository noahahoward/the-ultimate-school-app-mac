import Foundation

/// Throws away anything the model reported that isn't actually in the screenshot.
///
/// This is what makes "never guess" a property of the system rather than a request
/// in a prompt. A model can be told not to invent a due date and still do it; it
/// cannot invent one that survives being looked up in the recognized text.
enum EvidenceCheck {

    struct Outcome: Equatable {
        var fields: ExtractedFields
        var rejected: [RejectedField]
    }

    static func verify(_ fields: ExtractedFields, against ocrText: String) -> Outcome {
        let haystack = normalize(ocrText)
        var kept = fields
        var rejected: [RejectedField] = []

        func check(_ name: String, _ value: String) -> String {
            // OCR splits long headings across lines, so a correct title can arrive
            // with a newline in it. Collapse to single spaces before storing.
            let trimmed = value
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            guard !trimmed.isEmpty else { return "" }
            guard isSupported(trimmed, by: haystack) else {
                rejected.append(RejectedField(
                    name: name, value: trimmed,
                    reason: "not found in the screenshot"
                ))
                return ""
            }
            return trimmed
        }

        kept.title = check("Title", fields.title)
        kept.teacher = check("Teacher", fields.teacher)
        kept.className = check("Class", fields.className)
        kept.dueDateText = check("Due date", fields.dueDateText)
        kept.assignedDateText = check("Assigned date", fields.assignedDateText)
        kept.pointsText = check("Points", fields.pointsText)
        kept.statusText = check("Status", fields.statusText)

        var attachments: [String] = []
        for (index, value) in fields.attachments.enumerated() {
            let result = check("Attachment \(index + 1)", value)
            guard !result.isEmpty else { continue }
            // "Google Docs" is the file's type, printed on every attachment card.
            // It identifies nothing, and small models reach for it repeatedly.
            guard !isFileTypeLabel(result) else { continue }
            guard !attachments.contains(result) else { continue }
            attachments.append(result)
        }
        kept.attachments = attachments

        // The summary is the one field that isn't copied, so it can't be checked
        // against the screenshot. It can at least be rejected when it is plainly
        // just a button the model latched onto.
        let summary = fields.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        kept.summary = HeuristicExtractor.isChrome(summary) ? "" : summary

        return Outcome(fields: kept, rejected: rejected)
    }

    /// OCR splits a screenshot into lines, so a value can be real yet span a line
    /// break. Comparing against whitespace-collapsed text handles that without
    /// loosening the check into uselessness.
    static func isSupported(_ value: String, by normalizedHaystack: String) -> Bool {
        let needle = normalize(value)
        guard !needle.isEmpty else { return false }
        if normalizedHaystack.contains(needle) { return true }

        // Truncated UI labels ("!2026 Summer Home…") are genuinely on screen, so
        // match the part before the ellipsis rather than discarding the field.
        if let truncated = needle.split(separator: "…").first.map(String.init),
           truncated.count >= 6,
           normalizedHaystack.contains(truncated) {
            return true
        }
        if needle.hasSuffix("...") {
            let stem = String(needle.dropLast(3))
            if stem.count >= 6, normalizedHaystack.contains(stem) { return true }
        }
        return false
    }

    private static let fileTypeLabels: Set<String> = [
        "google docs", "google slides", "google sheets", "google drive",
        "pdf", "document", "spreadsheet", "presentation", "image", "video",
        "link", "file", "youtube",
    ]

    static func isFileTypeLabel(_ value: String) -> Bool {
        fileTypeLabels.contains(normalize(value))
    }

    /// Lowercases and collapses runs of whitespace. Punctuation is deliberately
    /// kept — dropping it would let "Aug 26" match "Aug 262".
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
