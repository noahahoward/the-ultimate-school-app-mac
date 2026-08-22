import Foundation

/// One class as read off a schedule, before anything is saved.
struct ClassDraft: Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var period: Int?
    /// 0 = all year, 1 = first semester, 2 = second.
    var semester = 0
    var teacher = ""
    var room = ""
    var startMinutes: Int?
    var endMinutes: Int?
    /// Nil when the schedule doesn't print meeting days, in which case the
    /// import falls back to a normal school week.
    var weekdays: Set<Int>?
    /// The line this came from, shown in review so a misread is obvious.
    var sourceLine = ""
    var include = true

    var semesterLabel: String {
        switch semester {
        case 1: "Semester 1"
        case 2: "Semester 2"
        default: "All year"
        }
    }
}

struct ScheduleDraft: Equatable, Sendable {
    var rows: [ClassDraft] = []
    var rejected: [RejectedField] = []
    /// Present when the schedule came from the table reader, so the column
    /// mapping stays adjustable in review.
    var table: DetectedTable?
    var roles: [ColumnRole] = []

    var isUsable: Bool { !rows.isEmpty }
    var isColumnMapped: Bool { table?.isUsable == true && !roles.isEmpty }
}

/// Reads a schedule listing without a model.
///
/// School schedules print one predictable detail line per class — "Period 3 -
/// SEMESTER 1", "Per 4 · Rm 118", "2nd Period 9:02-9:54". Finding that line and
/// taking the text above it as the course name gets the whole timetable with no
/// guessing at all, which is why this runs before the model rather than after.
enum ScheduleParsing {

    static func rows(from ocr: OCRResult) -> [ClassDraft] {
        var drafts: [ClassDraft] = []
        let lines = ocr.lines.map { $0.text }

        for (index, line) in lines.enumerated() {
            guard let periodNumber = period(in: line) else { continue }

            // The course name is the nearest line above that isn't itself a
            // detail line, so a stray header can't be mistaken for a class.
            var name = ""
            var cursor = index - 1
            while cursor >= 0 {
                let candidate = lines[cursor]
                if period(in: candidate) == nil, !isNoise(candidate) {
                    name = candidate
                    break
                }
                cursor -= 1
            }
            guard !name.isEmpty else { continue }

            var draft = ClassDraft()
            draft.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.period = periodNumber
            draft.semester = semester(in: line) ?? 0
            draft.room = room(in: line)
            draft.sourceLine = line
            let times = timeRange(in: line)
            draft.startMinutes = times?.start
            draft.endMinutes = times?.end
            drafts.append(draft)
        }

        return normalizeNames(drafts)
    }

    // MARK: - Field patterns

    /// "Period 3", "Per 3", "P3", "3rd Period".
    static func period(in line: String) -> Int? {
        let lower = line.lowercased()
        for marker in ["period ", "per ", "prd ", "p"] {
            var search = lower.startIndex
            while let range = lower.range(of: marker, range: search..<lower.endIndex) {
                let digits = lower[range.upperBound...].prefix { $0.isNumber }
                if let value = Int(digits), (1...12).contains(value) { return value }
                search = range.upperBound
                if search >= lower.endIndex { break }
            }
        }
        // "3rd Period" — the number leads instead of follows.
        if lower.contains("period"), let head = lower.split(whereSeparator: { $0.isWhitespace }).first {
            let digits = head.prefix { $0.isNumber }
            if let value = Int(digits), (1...12).contains(value) { return value }
        }
        return nil
    }

    static func semester(in line: String) -> Int? {
        let lower = line.lowercased()
        for marker in ["semester ", "sem ", "s"] {
            guard let range = lower.range(of: marker) else { continue }
            let digits = lower[range.upperBound...].prefix { $0.isNumber }
            if let value = Int(digits), (1...2).contains(value) { return value }
        }
        if lower.contains("full year") || lower.contains("year long") || lower.contains("yearlong") { return 0 }
        return nil
    }

    static func room(in line: String) -> String {
        let lower = line.lowercased()
        for marker in ["room ", "rm ", "rm."] {
            guard let range = lower.range(of: marker) else { continue }
            let value = line[range.upperBound...]
                .prefix { !$0.isWhitespace && $0 != "," && $0 != "-" && $0 != "·" }
            if !value.isEmpty { return String(value) }
        }
        return ""
    }

    /// Pulls a start and end time out of a detail line, wherever they sit in it:
    /// "9:02-9:54", "Period 3 - Room 204 - 9:02 AM - 9:54 AM".
    static func timeRange(in line: String) -> (start: Int, end: Int)? {
        let times = clockTimes(in: line)
        guard times.count >= 2 else { return nil }
        let start = times[0]
        var end = times[1]
        // An afternoon end written without AM/PM reads as morning: a class
        // running 12:40 to 1:32 would otherwise appear to end before it starts.
        if end <= start, end + 12 * 60 > start { end += 12 * 60 }
        guard end > start else { return nil }
        return (start, end)
    }

    /// Every clock time in a line, in order, pairing "9:02" with a following "AM".
    static func clockTimes(in line: String) -> [Int] {
        // Dashes are separators here, not characters: schedules write ranges both
        // as "9:02 AM - 9:54 AM" and as "9:02-9:54", and the second is one token
        // until the dash is split on.
        let tokens = line
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "\u{2013}" || $0 == "\u{2014}" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",;\u{00B7}|")) }

        var found: [Int] = []
        for (index, token) in tokens.enumerated() {
            let cleaned = token.lowercased()
            guard cleaned.contains(":") else { continue }

            var candidate = cleaned
            if index + 1 < tokens.count {
                let next = tokens[index + 1].lowercased()
                if next.hasPrefix("am") || next.hasPrefix("pm") {
                    candidate = cleaned + String(next.prefix(2))
                }
            }
            guard var minutes = QuickAddParser.clockTime(candidate) else { continue }
            // School days run morning to late afternoon, so a bare "1:15" is
            // the afternoon rather than the small hours.
            if !candidate.contains("am"), !candidate.contains("pm"), minutes < 7 * 60 {
                minutes += 12 * 60
            }
            found.append(minutes)
        }
        return found
    }

    /// Lines that are page furniture rather than a course.
    static func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.count < 2 { return true }
        let furniture = [
            "schedule", "course", "courses", "class", "classes", "term", "terms",
            "teacher", "room", "period", "semester", "days", "meeting days", "print",
        ]
        return furniture.contains(lower)
    }

    // MARK: - Roman numeral halves

    /// Strips the "I"/"II" suffix schools use to mark the two halves of a
    /// year-long course, but only where the schedule itself proves that is what
    /// the suffix means.
    ///
    /// OCR mangles those numerals badly — "BIOLOGY I!", "SPANISH 21" — so this
    /// cannot key off spelling. Instead it strips only when two rows collapse to
    /// the same name in different semesters, which leaves a genuine "Algebra 1"
    /// alone because nothing pairs with it.
    static func normalizeNames(_ rows: [ClassDraft]) -> [ClassDraft] {
        var bases: [String: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            bases[baseName(row.name).lowercased(), default: []].append(index)
        }

        var result = rows
        for (_, indexes) in bases where indexes.count >= 2 {
            let semesters = Set(indexes.map { rows[$0].semester })
            // Two rows sharing a base name across different semesters: the
            // suffix was a semester marker, not part of the course name.
            guard semesters.count >= 2 else { continue }
            for index in indexes {
                result[index].name = baseName(rows[index].name)
            }
        }
        return result
    }

    /// Removes a trailing roman-numeral-ish run, including the shapes OCR
    /// produces for it: I, II, l, ll, !, 1, and digits fused onto the numeral.
    static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var last = trimmed.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) else {
            return trimmed
        }
        let romanish = Set("Il1!|i")
        let head = String(trimmed.dropLast(last.count)).trimmingCharacters(in: .whitespaces)

        // A whole trailing token of numeral shapes: "II", "I!", "1".
        if last.allSatisfy({ romanish.contains($0) }), !head.isEmpty {
            return head
        }
        // The numeral fused onto the course number: "SPANISH 21", "ENGLISH 91".
        let suffix = String(last.reversed().prefix { romanish.contains($0) }.reversed())
        if !suffix.isEmpty, suffix.count <= 2 {
            last.removeLast(suffix.count)
            if !last.isEmpty, last.allSatisfy(\.isNumber) {
                return (head.isEmpty ? last : head + " " + last)
            }
        }
        return trimmed
    }
}
