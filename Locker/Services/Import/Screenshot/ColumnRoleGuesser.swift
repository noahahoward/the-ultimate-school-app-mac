import Foundation

/// Works out what each column of a detected table holds.
///
/// The student can correct any of it, but guessing well means most schedules
/// import without a single tap. Every test here is a plain content check — does
/// this column look like times, like periods, like names — so it behaves the
/// same on every Mac with no model involved.
enum ColumnRoleGuesser {

    static func guess(for table: DetectedTable) -> [ColumnRole] {
        guard table.columnCount > 0 else { return [] }

        var roles = [ColumnRole](repeating: .ignore, count: table.columnCount)
        var scores: [(index: Int, role: ColumnRole, confidence: Double)] = []

        for index in 0..<table.columnCount {
            let cells = table.column(index).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !cells.isEmpty else { continue }

            for role in [ColumnRole.times, .period, .term, .days, .room, .teacher] {
                let share = fraction(of: cells) { matches($0, role: role) }
                if share >= 0.6 { scores.append((index, role, share)) }
            }
        }

        // Strongest signal first, and one column per role.
        var takenRoles = Set<ColumnRole>()
        for candidate in scores.sorted(by: { $0.confidence > $1.confidence }) {
            guard roles[candidate.index] == .ignore, !takenRoles.contains(candidate.role) else { continue }
            roles[candidate.index] = candidate.role
            takenRoles.insert(candidate.role)
        }

        // Whatever is left with the most words is the class name: it is the one
        // column that is prose rather than a code.
        if !roles.contains(.className) {
            let remaining = (0..<table.columnCount).filter { roles[$0] == .ignore }
            if let best = remaining.max(by: { wordiness(table.column($0)) < wordiness(table.column($1)) }),
               wordiness(table.column(best)) > 0 {
                roles[best] = .className
            }
        }
        return roles
    }

    static func matches(_ cell: String, role: ColumnRole) -> Bool {
        let text = cell.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }

        switch role {
        case .times:
            return ScheduleFieldParsing.times(from: text) != nil
        case .period:
            return ScheduleFieldParsing.period(from: text) != nil
        case .term:
            let lower = text.lowercased()
            return lower.contains("semester") || lower.contains("term")
                || lower.contains("full year") || lower.contains("quarter")
                || lower == "s1" || lower == "s2" || lower == "fall" || lower == "spring"
        case .days:
            // Must be nothing but day names, or a teacher column of "SMITH, J"
            // reads as Monday and Tuesday.
            return ScheduleFieldParsing.isDayList(text)
        case .room:
            guard text.count <= 8 else { return false }
            let lower = text.lowercased()
            if lower.hasPrefix("rm") || lower.hasPrefix("room") { return true }
            // A bare number too large to be a period is almost always a room.
            guard text.allSatisfy({ $0.isNumber }), let value = Int(text) else { return false }
            return value > 12
        case .teacher:
            return looksLikeAName(text)
        case .className, .ignore:
            return false
        }
    }

    /// Teacher columns hold people, recognised by a title or by gradebook order.
    ///
    /// Two capitalised words is deliberately *not* enough: "Physical Science" and
    /// "World Geography" would qualify, and the class column would be read as the
    /// teacher. Where a teacher is written plainly as "Serena Sturgill" the column
    /// is genuinely ambiguous, so it is left for the student to assign.
    static func looksLikeAName(_ text: String) -> Bool {
        let lower = text.lowercased()
        let titles = ["mr.", "mrs.", "ms.", "mr ", "mrs ", "ms ", "dr.", "dr ", "coach ", "sra ", "srta ", "prof"]
        if titles.contains(where: { lower.hasPrefix($0) }) { return true }

        // "Surname, F" or "Surname, Firstname".
        guard text.contains(",") else { return false }
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "\'" } }
    }

    /// How much prose a column holds, used to find the class-name column.
    static func wordiness(_ cells: [String]) -> Double {
        let filled = cells.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !filled.isEmpty else { return 0 }
        let words = filled.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
        let letters = filled.reduce(0) { $0 + $1.filter(\.isLetter).count }
        return Double(words) / Double(filled.count) + Double(letters) / Double(filled.count) / 10
    }

    private static func fraction(of cells: [String], where test: (String) -> Bool) -> Double {
        guard !cells.isEmpty else { return 0 }
        return Double(cells.filter(test).count) / Double(cells.count)
    }
}

/// Turns a mapped table into classes.
enum TableScheduleBuilder {

    private static let headerWords: Set<String> = [
        "course", "courses", "class", "classes", "period", "per", "term", "semester",
        "teacher", "instructor", "room", "time", "times", "days", "meeting", "section",
    ]

    static func rows(from table: DetectedTable, roles: [ColumnRole]) -> [ClassDraft] {
        guard let nameIndex = roles.firstIndex(of: .className) else { return [] }

        return table.rows.compactMap { cells -> ClassDraft? in
            guard nameIndex < cells.count else { return nil }
            let name = cells[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            // The header row labels the columns; it is not a class.
            guard !headerWords.contains(name.lowercased()) else { return nil }

            var draft = ClassDraft()
            draft.name = name

            for (index, role) in roles.enumerated() where index < cells.count {
                let value = cells[index].trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { continue }
                switch role {
                case .period: draft.period = ScheduleFieldParsing.period(from: value)
                case .term: draft.semester = ScheduleFieldParsing.semester(from: value)
                case .teacher: draft.teacher = value
                case .room: draft.room = value
                case .days: draft.weekdays = ScheduleFieldParsing.weekdays(from: value)
                case .times:
                    if let times = ScheduleFieldParsing.times(from: value) {
                        draft.startMinutes = times.start
                        draft.endMinutes = times.end
                    }
                case .className, .ignore: break
                }
            }

            draft.sourceLine = cells.filter { !$0.isEmpty }.joined(separator: " · ")
            return draft
        }
    }
}
