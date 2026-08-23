import Foundation

/// Turns the verbatim strings from a screenshot into typed values.
///
/// Deliberately plain Swift: the model is never asked what date "Aug 26" is, only
/// to point at the text "Aug 26". Every interpretation happens here, where it is
/// deterministic and testable.
enum FieldParsing {

    private static let leadIns = ["due", "posted", "assigned", "on", "by", "date"]

    /// Parses the date labels found in school software: "Aug 26", "August 26",
    /// "Jun 17", "8/26", "Aug 26, 2026", "Due Aug 26".
    ///
    /// A date with no year is read as the next occurrence on or after `now`,
    /// because school screenshots almost never spell the year out.
    static func date(from raw: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        var words = raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":·|")) }
            .filter { !$0.isEmpty }

        while let first = words.first, leadIns.contains(first) { words.removeFirst() }
        guard !words.isEmpty else { return nil }

        // "8/26" or "8/26/2026"
        if let slashDate = numericDate(words[0], now: now, calendar: calendar) { return slashDate }

        // "aug 26" / "august 26th"
        guard let month = Month.parse(words[0]) else { return nil }
        guard words.count > 1, let day = dayNumber(words[1]) else { return nil }

        if words.count > 2, let year = Int(words[2]), year > 1900 {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            return realDate(from: comps, calendar: calendar)
        }
        return nextOccurrence(month: month, day: day, onOrAfter: now, calendar: calendar)
    }

    static func numericDate(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let parts = word.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard parts.count == 2 || parts.count == 3,
              let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        if parts.count == 3, let rawYear = Int(parts[2]) {
            var comps = DateComponents()
            comps.year = rawYear < 100 ? 2000 + rawYear : rawYear
            comps.month = month; comps.day = day
            return realDate(from: comps, calendar: calendar)
        }
        return nextOccurrence(month: month, day: day, onOrAfter: now, calendar: calendar)
    }

    static func dayNumber(_ word: String) -> Int? {
        let digits = word.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), (1...31).contains(value) else { return nil }
        let suffix = word.dropFirst(digits.count)
        guard suffix.isEmpty || ["st", "nd", "rd", "th"].contains(String(suffix)) else { return nil }
        return value
    }

    /// A month/day with no year lands within six months either side of today, so
    /// a screenshot taken in August reads "Jun 17" as the June just gone rather
    /// than one ten months away.
    static func nextOccurrence(month: Int, day: Int, onOrAfter now: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year], from: now)
        comps.month = month
        comps.day = day
        guard let thisYear = realDate(from: comps, calendar: calendar) else { return nil }

        let today = calendar.startOfDay(for: now)
        let sixMonths: TimeInterval = 182 * 24 * 3600
        if thisYear >= today.addingTimeInterval(-sixMonths) { return thisYear }

        comps.year = (comps.year ?? 2000) + 1
        return realDate(from: comps, calendar: calendar)
    }

    /// Builds a date only if it actually exists.
    ///
    /// `Calendar` quietly rolls impossible dates forward — 31 September becomes
    /// 1 October, 30 February becomes 2 March — so OCR noise that fuses a stray
    /// digit onto a day would produce a confident, wrong due date.
    static func realDate(from comps: DateComponents, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: comps) else { return nil }
        let rebuilt = calendar.dateComponents([.year, .month, .day], from: date)
        guard rebuilt.year == comps.year,
              rebuilt.month == comps.month,
              rebuilt.day == comps.day else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// "Wed, Aug 26, 11:59 PM" and the like: a weekday that adds nothing, a
    /// date, and a time that matters.
    ///
    /// Returns whether a real time was given, because "due at 11:59 PM" and
    /// "due that day" deserve different reminders.
    static func dateAndTime(
        from raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (date: Date, hasTime: Bool)? {
        let cleaned = raw
            .replacingOccurrences(of: "\u{202F}", with: " ")   // narrow no-break space
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var dayPart = cleaned
        var timePart: String?

        if parts.count >= 2 {
            // A leading weekday is decoration; the date is the first part that
            // names a month or looks numeric.
            let withoutWeekday = parts.filter { Weekday.parse($0.lowercased()) == nil }
            dayPart = withoutWeekday.first ?? parts[0]
            timePart = withoutWeekday.dropFirst().first { $0.contains(":") }
        } else if let range = cleaned.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) {
            timePart = String(cleaned[range.lowerBound...])
            dayPart = String(cleaned[..<range.lowerBound])
        }

        guard let day = date(from: dayPart, now: now, calendar: calendar) else { return nil }
        guard let timePart, let minutes = ScheduleParsing.clockTimes(in: timePart).first else {
            return (day, false)
        }
        return (ScheduleEngine.date(day, atMinutes: minutes, calendar: calendar), true)
    }

    /// "4 points" -> 4. "100 pts" -> 100. "Ungraded" -> nil.
    static func points(from raw: String) -> Double? {
        let digits = raw.unicodeScalars
            .split(whereSeparator: { !CharacterSet(charactersIn: "0123456789.").contains($0) })
            .map(String.init)
        guard let first = digits.first, let value = Double(first), value >= 0 else { return nil }
        return value
    }

    /// Maps a status label to done/not done. Anything unrecognized stays nil so
    /// the importer leaves the assignment alone rather than guessing.
    ///
    /// Negations are tested first, and it matters enormously: every one of them
    /// contains the word it negates. "Not submitted" contains "submitted", and
    /// checking the positive list first marks unfinished work as done — the
    /// worst thing a planner can get wrong.
    static func isTurnedIn(from raw: String) -> Bool? {
        let text = raw.lowercased()

        let notDone = [
            "not turned in", "not submitted", "not handed in", "not done",
            "unsubmitted", "incomplete", "no submission", "missing",
            "assigned", "to do", "past due", "late",
        ]
        if notDone.contains(where: { text.contains($0) }) { return false }

        let done = ["turned in", "handed in", "submitted", "returned", "done", "complete"]
        if done.contains(where: { text.contains($0) }) { return true }

        return nil
    }

    /// Reuses the same keyword table the typing shortcut uses, so a screenshot and
    /// a typed line classify the same way.
    static func type(fromTitle title: String, attachments: [String] = []) -> AssignmentType {
        let text = (title + " " + attachments.joined(separator: " ")).lowercased()
        let keywords: [(String, AssignmentType)] = [
            ("final exam", .test), ("midterm", .test), ("exam", .test), ("test", .test),
            ("quiz", .quiz),
            ("lab", .lab),
            ("essay", .essay), ("paper", .essay),
            ("project", .project),
            ("presentation", .presentation), ("speech", .presentation),
            ("read", .reading), ("chapter", .reading),
            ("homework", .homework), ("worksheet", .homework), ("packet", .homework),
        ]
        for (needle, type) in keywords where text.contains(needle) { return type }
        return .homework
    }

    /// Assembles the verified slots into something the review sheet can show.
    static func draft(from fields: ExtractedFields, rejected: [RejectedField], now: Date = Date(), calendar: Calendar = .current) -> ImportDraft {
        var draft = ImportDraft()
        draft.title = fields.title
        draft.teacher = fields.teacher
        draft.className = fields.className
        draft.summary = fields.summary
        draft.attachments = fields.attachments
        draft.rejected = rejected

        draft.dueDateText = fields.dueDateText
        draft.dueAt = date(from: fields.dueDateText, now: now, calendar: calendar)

        draft.assignedDateText = fields.assignedDateText
        draft.assignedAt = date(from: fields.assignedDateText, now: now, calendar: calendar)

        draft.pointsText = fields.pointsText
        draft.maxPoints = points(from: fields.pointsText)

        draft.statusText = fields.statusText
        draft.isTurnedIn = isTurnedIn(from: fields.statusText)

        draft.type = type(fromTitle: fields.title, attachments: fields.attachments)
        return draft
    }
}
