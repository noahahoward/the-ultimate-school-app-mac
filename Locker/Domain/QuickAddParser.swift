import Foundation

/// A class as the parser sees it: an identity plus the words that should match it.
public struct ClassRef: Equatable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    /// Used to default an assignment's due time to when the class meets.
    public var startMinutes: Int?

    public init(id: String, name: String, aliases: [String] = [], startMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.startMinutes = startMinutes
    }
}

public struct ParsedQuickAdd: Equatable, Sendable {
    public var title: String
    public var classID: String?
    public var dueAt: Date?
    public var hasDueTime: Bool
    public var type: AssignmentType
    public var priority: Priority
    public var estimatedMinutes: Int?
    /// True when the text explicitly said something about a date.
    public var matchedDate: Bool

    public init(
        title: String,
        classID: String? = nil,
        dueAt: Date? = nil,
        hasDueTime: Bool = false,
        type: AssignmentType = .homework,
        priority: Priority = .normal,
        estimatedMinutes: Int? = nil,
        matchedDate: Bool = false
    ) {
        self.title = title
        self.classID = classID
        self.dueAt = dueAt
        self.hasDueTime = hasDueTime
        self.type = type
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.matchedDate = matchedDate
    }
}

/// Turns one line of typing into an assignment.
///
/// `bio lab report due fri` -> Biology, "Lab report", due Friday
/// `!! apush essay next tue at 8am 90m` -> APUSH, "Essay", high priority, Tuesday 8:00, 90 min
public enum QuickAddParser {

    public static func parse(
        _ input: String,
        classes: [ClassRef] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedQuickAdd {
        var tokens = Tokenizer.tokens(from: input)
        guard !tokens.isEmpty else { return ParsedQuickAdd(title: "") }

        var result = ParsedQuickAdd(title: "")

        // Order matters: class names can contain digits ("Algebra 2"), so match
        // them before the date scanner gets a chance to read "2" as a day.
        matchClass(&tokens, classes: classes, into: &result)
        matchPriority(&tokens, into: &result)
        matchDuration(&tokens, into: &result)
        let time = matchTime(&tokens)
        matchDate(&tokens, now: now, calendar: calendar, explicitTime: time, into: &result)
        matchType(&tokens, into: &result)

        // A time with no date means "today", or tomorrow if that moment already passed.
        if result.dueAt == nil, let time {
            var day = calendar.startOfDay(for: now)
            if ScheduleEngine.date(day, atMinutes: time, calendar: calendar) < now {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            result.dueAt = ScheduleEngine.date(day, atMinutes: time, calendar: calendar)
            result.hasDueTime = true
            result.matchedDate = true
        }

        result.title = buildTitle(from: tokens, fallback: result.type)
        return result
    }

    // MARK: - Class

    private static func matchClass(_ tokens: inout [Token], classes: [ClassRef], into result: inout ParsedQuickAdd) {
        guard !classes.isEmpty else { return }

        var best: (classID: String, range: Range<Int>, score: Int)?

        // Longest phrase wins, so "world history" beats a stray "history".
        for length in stride(from: min(4, tokens.count), through: 1, by: -1) {
            for start in 0...(max(0, tokens.count - length)) {
                let range = start..<(start + length)
                guard range.upperBound <= tokens.count else { continue }
                guard tokens[range].allSatisfy({ !$0.isConsumed }) else { continue }
                let phrase = tokens[range].map(\.normalized).joined(separator: " ")
                guard !phrase.isEmpty else { continue }

                for ref in classes {
                    guard let score = matchScore(phrase: phrase, ref: ref) else { continue }
                    let weighted = score + length * 10
                    if weighted > (best?.score ?? 0) {
                        best = (ref.id, range, weighted)
                    }
                }
            }
            if best != nil { break }
        }

        guard let best else { return }
        result.classID = best.classID
        for index in best.range { tokens[index].isConsumed = true }
    }

    /// Higher is a better match. Nil means no match at all.
    private static func matchScore(phrase: String, ref: ClassRef) -> Int? {
        let name = Tokenizer.normalize(ref.name)
        let aliases = ref.aliases.map(Tokenizer.normalize).filter { !$0.isEmpty }

        if phrase == name { return 100 }
        if aliases.contains(phrase) { return 90 }
        // Abbreviations the student didn't bother to configure: "bio" -> "biology i".
        if phrase.count >= 3, name.hasPrefix(phrase) { return 60 }
        if phrase.count >= 3, let firstWord = name.split(separator: " ").first, firstWord.hasPrefix(phrase) { return 55 }
        if phrase.count >= 4, name.contains(phrase) { return 40 }
        // Initialisms: "apush" for "AP US History" won't work, but "ap us history" will.
        if phrase.count >= 3, aliases.contains(where: { $0.hasPrefix(phrase) }) { return 50 }
        return nil
    }

    // MARK: - Priority

    private static func matchPriority(_ tokens: inout [Token], into result: inout ParsedQuickAdd) {
        for index in tokens.indices where !tokens[index].isConsumed {
            let word = tokens[index].normalized
            if word == "urgent" || word == "important" {
                result.priority = .high
                tokens[index].isConsumed = true
            } else if !tokens[index].text.isEmpty, tokens[index].text.allSatisfy({ $0 == "!" }) {
                result.priority = .high
                tokens[index].isConsumed = true
            }
        }
        // A trailing "!" stuck to the last word, e.g. "essay!!".
        if let last = tokens.lastIndex(where: { !$0.isConsumed }), tokens[last].text.hasSuffix("!") {
            result.priority = .high
            tokens[last].text = String(tokens[last].text.reversed().drop(while: { $0 == "!" }).reversed())
            if tokens[last].text.isEmpty { tokens[last].isConsumed = true }
        }
    }

    // MARK: - Duration

    private static func matchDuration(_ tokens: inout [Token], into result: inout ParsedQuickAdd) {
        for index in tokens.indices where !tokens[index].isConsumed {
            let word = tokens[index].normalized

            // Joined form: "30m", "90min", "2h"
            if let minutes = joinedDuration(word) {
                result.estimatedMinutes = minutes
                tokens[index].isConsumed = true
                continue
            }
            // Split form: "30 min", "2 hours"
            if let value = Int(word), value > 0, index + 1 < tokens.count, !tokens[index + 1].isConsumed {
                let unit = tokens[index + 1].normalized
                if let minutes = duration(value: value, unit: unit) {
                    result.estimatedMinutes = minutes
                    tokens[index].isConsumed = true
                    tokens[index + 1].isConsumed = true
                }
            }
        }
    }

    private static func joinedDuration(_ word: String) -> Int? {
        let digits = word.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        return duration(value: value, unit: String(word.dropFirst(digits.count)))
    }

    private static func duration(value: Int, unit: String) -> Int? {
        switch unit {
        case "m", "min", "mins", "minute", "minutes": return value
        case "h", "hr", "hrs", "hour", "hours": return value * 60
        default: return nil
        }
    }

    // MARK: - Time of day

    /// Returns minutes-from-midnight when the text names a time.
    private static func matchTime(_ tokens: inout [Token]) -> Int? {
        for index in tokens.indices where !tokens[index].isConsumed {
            let word = tokens[index].normalized

            if word == "noon" { tokens[index].isConsumed = true; consumeTimeLeadIn(&tokens, before: index); return 12 * 60 }
            if word == "midnight" { tokens[index].isConsumed = true; consumeTimeLeadIn(&tokens, before: index); return 23 * 60 + 59 }

            if let minutes = clockTime(word) {
                tokens[index].isConsumed = true
                consumeTimeLeadIn(&tokens, before: index)
                return minutes
            }
            // Split form: "3 pm"
            if index + 1 < tokens.count, !tokens[index + 1].isConsumed {
                let suffix = tokens[index + 1].normalized
                if suffix == "pm" || suffix == "am", let minutes = clockTime(word + suffix) {
                    tokens[index].isConsumed = true
                    tokens[index + 1].isConsumed = true
                    consumeTimeLeadIn(&tokens, before: index)
                    return minutes
                }
            }
        }
        return nil
    }

    /// Drops the "at"/"by"/"@" that introduced a time so it doesn't land in the title.
    private static func consumeTimeLeadIn(_ tokens: inout [Token], before index: Int) {
        guard index > 0 else { return }
        let word = tokens[index - 1].normalized
        if word == "at" || word == "by" || word == "@" { tokens[index - 1].isConsumed = true }
    }

    /// Parses "3pm", "3:30pm", "15:00", "1130am".
    static func clockTime(_ word: String) -> Int? {
        var body = word
        var meridiem: String?
        if body.hasSuffix("pm") { meridiem = "pm"; body = String(body.dropLast(2)) }
        else if body.hasSuffix("am") { meridiem = "am"; body = String(body.dropLast(2)) }
        else if body.hasSuffix("p") && body.count > 1 { meridiem = "pm"; body = String(body.dropLast()) }
        else if body.hasSuffix("a") && body.count > 1 { meridiem = "am"; body = String(body.dropLast()) }
        body = body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        var hour = 0
        var minute = 0

        if body.contains(":") {
            let parts = body.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hour = h; minute = m
        } else {
            guard body.allSatisfy(\.isNumber), let value = Int(body) else { return nil }
            switch body.count {
            case 1, 2:
                // A bare number is only a time when something marked it as one.
                guard meridiem != nil else { return nil }
                hour = value
            case 3: hour = value / 100; minute = value % 100
            case 4: hour = value / 100; minute = value % 100
            default: return nil
            }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }
        return hour * 60 + minute
    }

    // MARK: - Date

    private static func matchDate(
        _ tokens: inout [Token],
        now: Date,
        calendar: Calendar,
        explicitTime: Int?,
        into result: inout ParsedQuickAdd
    ) {
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var consumed: [Int] = []

        outer: for index in tokens.indices where !tokens[index].isConsumed {
            let word = tokens[index].normalized
            let next = tokens.indices.contains(index + 1) && !tokens[index + 1].isConsumed
                ? tokens[index + 1].normalized : nil
            let after = tokens.indices.contains(index + 2) && !tokens[index + 2].isConsumed
                ? tokens[index + 2].normalized : nil

            switch word {
            case "today", "tonight":
                day = today; consumed = [index]; break outer
            case "tomorrow", "tmrw", "tmr", "tmw":
                day = calendar.date(byAdding: .day, value: 1, to: today); consumed = [index]; break outer
            case "eod":
                day = today; consumed = [index]; break outer
            case "next":
                if let next, let weekday = Weekday.parse(next) {
                    day = nextOccurrence(of: weekday, after: today, calendar: calendar, skippingAWeek: true)
                    consumed = [index, index + 1]; break outer
                }
                if let next, next == "week" {
                    day = calendar.date(byAdding: .day, value: 7, to: today)
                    consumed = [index, index + 1]; break outer
                }
            case "this":
                if let next, let weekday = Weekday.parse(next) {
                    day = nextOccurrence(of: weekday, after: today, calendar: calendar, skippingAWeek: false)
                    consumed = [index, index + 1]; break outer
                }
            case "in":
                if let next, let value = Int(next), let unit = after {
                    if unit.hasPrefix("day") {
                        day = calendar.date(byAdding: .day, value: value, to: today)
                        consumed = [index, index + 1, index + 2]; break outer
                    }
                    if unit.hasPrefix("week") {
                        day = calendar.date(byAdding: .day, value: value * 7, to: today)
                        consumed = [index, index + 1, index + 2]; break outer
                    }
                }
            default:
                if let weekday = Weekday.parse(word) {
                    day = nextOccurrence(of: weekday, after: today, calendar: calendar, skippingAWeek: false)
                    consumed = [index]; break outer
                }
                if let month = Month.parse(word), let next, let dayNumber = dayNumber(next) {
                    day = date(month: month, day: dayNumber, onOrAfter: today, calendar: calendar)
                    consumed = [index, index + 1]; break outer
                }
                if let parsed = numericDate(word, onOrAfter: today, calendar: calendar) {
                    day = parsed; consumed = [index]; break outer
                }
            }
        }

        guard let day else { return }
        for index in consumed where tokens.indices.contains(index) { tokens[index].isConsumed = true }
        // Drop the "due"/"on"/"by" that introduced the date.
        if let first = consumed.first, first > 0 {
            let lead = tokens[first - 1].normalized
            if ["due", "on", "by", "for"].contains(lead) { tokens[first - 1].isConsumed = true }
        }

        result.matchedDate = true
        if let explicitTime {
            result.dueAt = ScheduleEngine.date(day, atMinutes: explicitTime, calendar: calendar)
            result.hasDueTime = true
        } else {
            result.dueAt = day
            result.hasDueTime = false
        }
    }

    private static func dayNumber(_ word: String) -> Int? {
        let digits = word.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), (1...31).contains(value) else { return nil }
        let suffix = word.dropFirst(digits.count)
        guard suffix.isEmpty || ["st", "nd", "rd", "th"].contains(String(suffix)) else { return nil }
        return value
    }

    /// Handles "9/3", "9-3", "9/3/26".
    private static func numericDate(_ word: String, onOrAfter reference: Date, calendar: Calendar) -> Date? {
        let separators: Set<Character> = ["/", "-", "."]
        guard word.contains(where: { separators.contains($0) }) else { return nil }
        let parts = word.split(whereSeparator: { separators.contains($0) }).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        if parts.count == 3, let rawYear = Int(parts[2]) {
            let year = rawYear < 100 ? 2000 + rawYear : rawYear
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
        }
        return date(month: month, day: day, onOrAfter: reference, calendar: calendar)
    }

    /// Picks the next occurrence of a month/day, rolling into next year when it's already past.
    private static func date(month: Int, day: Int, onOrAfter reference: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year], from: reference)
        comps.month = month
        comps.day = day
        guard let candidate = calendar.date(from: comps) else { return nil }
        let start = calendar.startOfDay(for: candidate)
        if start >= calendar.startOfDay(for: reference) { return start }
        comps.year = (comps.year ?? 2000) + 1
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    /// Plain "tue" is the next Tuesday (today counts). "next tue" is the Tuesday of
    /// the following calendar week, which is what people mean even midweek.
    private static func nextOccurrence(
        of weekday: Int,
        after reference: Date,
        calendar: Calendar,
        skippingAWeek: Bool
    ) -> Date {
        guard skippingAWeek else {
            let current = calendar.component(.weekday, from: reference)
            let delta = (weekday - current + 7) % 7
            return calendar.date(byAdding: .day, value: delta, to: reference) ?? reference
        }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        guard let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return reference }
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: nextWeekStart) ?? nextWeekStart
    }

    // MARK: - Type

    private static func matchType(_ tokens: inout [Token], into result: inout ParsedQuickAdd) {
        for index in tokens.indices where !tokens[index].isConsumed {
            let word = tokens[index].normalized
            guard let match = typeKeywords[word] else { continue }
            result.type = match.type
            // Bare abbreviations carry no meaning in a title, so they get eaten.
            if match.consume { tokens[index].isConsumed = true }
            return
        }
    }

    private static let typeKeywords: [String: (type: AssignmentType, consume: Bool)] = [
        "hw": (.homework, true),
        "hmwk": (.homework, true),
        "homework": (.homework, false),
        "assignment": (.homework, false),
        "worksheet": (.homework, false),
        "packet": (.homework, false),
        "problems": (.homework, false),
        "test": (.test, false),
        "exam": (.test, false),
        "final": (.test, false),
        "midterm": (.test, false),
        "quiz": (.quiz, false),
        "project": (.project, false),
        "essay": (.essay, false),
        "paper": (.essay, false),
        "writeup": (.essay, false),
        "read": (.reading, false),
        "reading": (.reading, false),
        "chapter": (.reading, false),
        "ch": (.reading, true),
        "lab": (.lab, false),
        "presentation": (.presentation, false),
        "present": (.presentation, false),
        "speech": (.presentation, false),
    ]

    // MARK: - Title

    private static let fillerWords: Set<String> = ["due", "on", "by", "for", "at", "the", "a", "an", "my", "is", "in"]

    private static func buildTitle(from tokens: [Token], fallback: AssignmentType) -> String {
        var words = tokens.filter { !$0.isConsumed }.map(\.text)

        while let first = words.first, fillerWords.contains(Tokenizer.normalize(first)) { words.removeFirst() }
        while let last = words.last, fillerWords.contains(Tokenizer.normalize(last)) { words.removeLast() }

        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return fallback.label }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}

// MARK: - Tokens

struct Token {
    var text: String
    var isConsumed: Bool = false
    var normalized: String { Tokenizer.normalize(text) }
}

enum Tokenizer {
    static func tokens(from input: String) -> [Token] {
        input
            .split(whereSeparator: { $0.isWhitespace })
            .map { Token(text: String($0)) }
    }

    /// Lowercases and strips the punctuation that would otherwise block a match,
    /// while keeping the characters dates, times, and multi-word names need.
    static func normalize(_ word: String) -> String {
        word.lowercased().filter { char in
            char.isLetter || char.isNumber || char == " "
                || char == ":" || char == "/" || char == "-" || char == "." || char == "@"
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
    }
}

enum Weekday {
    static let names: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "tuesd": 3,
        "wednesday": 4, "wed": 4, "weds": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]

    static func parse(_ word: String) -> Int? { names[word] }
}

enum Month {
    static let names: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    static func parse(_ word: String) -> Int? { names[word] }
}
