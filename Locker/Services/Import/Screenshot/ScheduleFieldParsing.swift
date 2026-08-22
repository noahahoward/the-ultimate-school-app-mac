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
    /// Two-letter forms are matched before one-letter ones so "Th" is Thursday
    /// rather than Tuesday followed by a stray letter.
    static func weekdays(from text: String) -> Set<Int>? {
        let lower = text.lowercased()
        guard !lower.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        if lower.contains("daily") || lower.contains("every day") || lower.contains("everyday") {
            return Weekdays.schoolWeek
        }
        if lower.contains("m-f") || lower.contains("mon-fri") || lower.contains("m - f") {
            return Weekdays.schoolWeek
        }

        let letters = lower.filter { $0.isLetter }
        guard !letters.isEmpty else { return nil }

        var days: Set<Int> = []
        var index = letters.startIndex
        while index < letters.endIndex {
            let remaining = letters[index...]
            if remaining.hasPrefix("th") { days.insert(5); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("tu") { days.insert(3); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("su") { days.insert(1); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("sa") { days.insert(7); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("mo") { days.insert(2); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("we") { days.insert(4); index = letters.index(index, offsetBy: 2); continue }
            if remaining.hasPrefix("fr") { days.insert(6); index = letters.index(index, offsetBy: 2); continue }

            switch letters[index] {
            case "m": days.insert(2)
            case "t": days.insert(3)
            case "w": days.insert(4)
            case "f": days.insert(6)
            // A lone "s" could be either weekend day, so it is left out rather
            // than guessed at.
            default: break
            }
            index = letters.index(after: index)
        }
        return days.isEmpty ? nil : days
    }

    static func times(from text: String) -> (start: Int, end: Int)? {
        ScheduleParsing.timeRange(in: text)
    }
}
