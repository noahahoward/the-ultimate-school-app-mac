import Foundation

/// Turns the loose strings a schedule prints into typed values.
///
/// Kept apart from the row-finding so it can serve both routes: the pattern
/// reader that handles familiar layouts, and the model that handles the rest.
/// Either way, the interpreting happens here in plain Swift.
enum ScheduleFieldParsing {

    /// "Period 3", "3rd", "P3", "3" -> 3
    ///
    /// A bare number only counts when the whole field is that number. Reading
    /// leading digits out of any string turns a 7:45 start time into period 7,
    /// which is exactly the mistake a model makes when it puts the wrong column
    /// in this field.
    static func period(from text: String) -> Int? {
        if let found = ScheduleParsing.period(in: text) { return found }

        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["st", "nd", "rd", "th"] where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(2))
        }
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber),
              let value = Int(trimmed), (1...12).contains(value) else { return nil }
        return value
    }

    /// "SEMESTER 1", "S2", "Fall", "Full Year" -> 1, 2, or 0 for all year.
    static func semester(from text: String) -> Int {
        let lower = text.lowercased()
        if lower.contains("full year") || lower.contains("year long")
            || lower.contains("yearlong") || lower.contains("both") { return 0 }
        if lower.contains("fall") || lower.contains("first") { return 1 }
        if lower.contains("spring") || lower.contains("second") { return 2 }
        if let found = ScheduleParsing.semester(in: text) { return found }
        return 0
    }

    /// The weekday letters schedules use: "M W F", "MWF", "Mon/Wed", "M-F", "Daily".
    ///
    /// Longer names are matched before shorter ones so "Th" is Thursday rather
    /// than Tuesday followed by a stray letter, and "Mon" is consumed whole.
    static func weekdays(from text: String) -> Set<Int>? {
        parseDays(text)?.days
    }

    /// True only when the text is *nothing but* a list of days.
    ///
    /// Without this, any short string containing an m or a t looks like a day
    /// list — a teacher column of "SMITH, J" reads as Monday and Tuesday.
    static func isDayList(_ text: String) -> Bool {
        guard let parsed = parseDays(text) else { return false }
        return parsed.fullyConsumed && !parsed.days.isEmpty
    }

    /// Day tokens longest-first, so multi-letter names win over single letters.
    private static let dayTokens: [(String, Int)] = [
        ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5),
        ("friday", 6), ("saturday", 7), ("sunday", 1),
        ("tues", 3), ("thur", 5), ("thurs", 5),
        ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7), ("sun", 1),
        ("th", 5), ("tu", 3), ("mo", 2), ("we", 4), ("fr", 6), ("sa", 7), ("su", 1),
        ("m", 2), ("t", 3), ("w", 4), ("f", 6),
    ]

    private static func parseDays(_ text: String) -> (days: Set<Int>, fullyConsumed: Bool)? {
        let lower = text.lowercased()
        guard !lower.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        if lower.contains("daily") || lower.contains("every day") || lower.contains("everyday")
            || lower.contains("m-f") || lower.contains("mon-fri") || lower.contains("m - f") {
            return (Weekdays.schoolWeek, true)
        }

        let letters = lower.filter { $0.isLetter }
        guard !letters.isEmpty else { return nil }

        var days: Set<Int> = []
        var consumedAll = true
        var index = letters.startIndex

        while index < letters.endIndex {
            let remaining = String(letters[index...])
            if let token = dayTokens.first(where: { remaining.hasPrefix($0.0) }) {
                days.insert(token.1)
                index = letters.index(index, offsetBy: token.0.count)
            } else {
                // A letter that is no part of any day name: this is not a day list.
                consumedAll = false
                index = letters.index(after: index)
            }
        }
        return days.isEmpty ? nil : (days, consumedAll)
    }

    static func times(from text: String) -> (start: Int, end: Int)? {
        ScheduleParsing.timeRange(in: text)
    }
}
