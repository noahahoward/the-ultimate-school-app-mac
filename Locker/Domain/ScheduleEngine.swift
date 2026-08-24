import Foundation

/// Everything the schedule math needs, lifted out of SwiftData so it can be tested directly.
public struct ScheduleConfig: Equatable, Sendable {
    public var kind: ScheduleKind
    public var schoolDays: Set<Int>
    public var abAnchorDate: Date?
    public var abAnchorIsA: Bool
    /// Dates the rotation starts over on a named letter.
    public var abResets: [ABReset]
    public var noSchoolDays: [Date]
    /// Dates when the timetable is set aside and every class meets — an
    /// introduction day, an assembly day, an exam review day.
    public var allClassDates: [Date]
    /// Weekdays that always work that way, for a school whose Friday is run
    /// differently from the rest of the week.
    public var allClassWeekdays: Set<Int>
    public var firstDayOfSchool: Date?
    public var lastDayOfSchool: Date?
    public var secondSemesterStart: Date?

    public init(
        kind: ScheduleKind = .weekly,
        schoolDays: Set<Int> = Weekdays.schoolWeek,
        abAnchorDate: Date? = nil,
        abAnchorIsA: Bool = true,
        abResets: [ABReset] = [],
        noSchoolDays: [Date] = [],
        allClassDates: [Date] = [],
        allClassWeekdays: Set<Int> = [],
        firstDayOfSchool: Date? = nil,
        lastDayOfSchool: Date? = nil,
        secondSemesterStart: Date? = nil
    ) {
        self.kind = kind
        self.schoolDays = schoolDays
        self.abAnchorDate = abAnchorDate
        self.abAnchorIsA = abAnchorIsA
        self.abResets = abResets
        self.noSchoolDays = noSchoolDays
        self.allClassDates = allClassDates
        self.allClassWeekdays = allClassWeekdays
        self.firstDayOfSchool = firstDayOfSchool
        self.lastDayOfSchool = lastDayOfSchool
        self.secondSemesterStart = secondSemesterStart
    }
}

/// The parts of a class the schedule cares about. `SchoolClass` conforms; tests use a struct.
public protocol ScheduleItem {
    var daysMask: Int { get }
    var abDesignation: ABDesignation { get }
    var startMinutes: Int? { get }
    var endMinutes: Int? { get }
    var period: Int? { get }
    var name: String { get }
    var isArchived: Bool { get }
    /// 0 = all year, 1 = first semester, 2 = second semester.
    var semester: Int { get }
}

/// A day the rotation is set back to a known letter, whatever came before it.
///
/// Districts differ on what a break does. Most carry the rotation across it —
/// the day off simply does not count. Others come back on a fixed letter every
/// time, and without saying so the whole term after a break reads inverted.
public struct ABReset: Equatable, Sendable, Codable, Identifiable {
    public var date: Date
    public var isA: Bool

    public var id: Date { date }

    public init(date: Date, isA: Bool) {
        self.date = date
        self.isA = isA
    }
}

public enum DayLetter: String, Sendable {
    case a = "A", b = "B"

    public var other: DayLetter { self == .a ? .b : .a }
}

public enum ScheduleEngine {

    // MARK: - School days

    public static func isSchoolDay(_ date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard config.schoolDays.contains(calendar.component(.weekday, from: day)) else { return false }
        if config.noSchoolDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) { return false }
        if let first = config.firstDayOfSchool, day < calendar.startOfDay(for: first) { return false }
        if let last = config.lastDayOfSchool, day > calendar.startOfDay(for: last) { return false }
        return true
    }

    // MARK: - A/B days

    /// The A/B letter for a date, or nil when the school doesn't use them or it isn't a school day.
    /// Which semester's timetable is in force on a date. Nil when the school
    /// never switches, in which case every class runs all year.
    public static func semester(on date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> Int? {
        guard let start = config.secondSemesterStart else { return nil }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: start) ? 1 : 2
    }

    /// A day the timetable is set aside for, when every class meets.
    ///
    /// It spends no letter: the alternation picks up on the far side exactly
    /// where it left off, which is what a school means by an introduction day
    /// or a Friday run differently.
    public static func isAllClassDay(
        _ date: Date, config: ScheduleConfig, calendar: Calendar = .current
    ) -> Bool {
        guard isSchoolDay(date, config: config, calendar: calendar) else { return false }
        let day = calendar.startOfDay(for: date)
        if config.allClassDates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            return true
        }
        return config.allClassWeekdays.contains(calendar.component(.weekday, from: day))
    }

    /// A school day that carries a letter — everything except the days set aside.
    static func isLetteredDay(
        _ date: Date, config: ScheduleConfig, calendar: Calendar = .current
    ) -> Bool {
        isSchoolDay(date, config: config, calendar: calendar)
            && !isAllClassDay(date, config: config, calendar: calendar)
    }

    /// Where the letters actually start.
    ///
    /// The anchor is normally the first day of school, but that day may be an
    /// introduction day belonging to neither letter. The count then starts from
    /// the first day that does carry one.
    public static func letteredAnchor(
        config: ScheduleConfig, calendar: Calendar = .current
    ) -> Date? {
        guard let anchor = config.abAnchorDate else { return nil }
        return nextLetteredDay(onOrAfter: anchor, config: config, calendar: calendar)
    }

    /// The first day from here forward that carries a letter.
    static func nextLetteredDay(
        onOrAfter date: Date, config: ScheduleConfig, calendar: Calendar = .current
    ) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        var guardrail = 0
        while !isLetteredDay(cursor, config: config, calendar: calendar), guardrail < 400 {
            guardrail += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return isLetteredDay(cursor, config: config, calendar: calendar) ? cursor : nil
    }

    /// Every point the rotation is known from, earliest first.
    ///
    /// The start of the year, plus each date it is set back to a named letter.
    /// Each is moved forward to a day that actually carries a letter, since a
    /// term often resumes on a day the school has set aside.
    static func anchors(config: ScheduleConfig, calendar: Calendar = .current) -> [ABReset] {
        var found: [ABReset] = []
        if let start = letteredAnchor(config: config, calendar: calendar) {
            found.append(ABReset(date: start, isA: config.abAnchorIsA))
        }
        for reset in config.abResets {
            guard let day = nextLetteredDay(onOrAfter: reset.date, config: config, calendar: calendar)
            else { continue }
            found.append(ABReset(date: day, isA: reset.isA))
        }
        // A later reset on the same day wins, so the student can correct one.
        var byDay: [Date: ABReset] = [:]
        for entry in found { byDay[calendar.startOfDay(for: entry.date)] = entry }
        return byDay.values.sorted { $0.date < $1.date }
    }

    public static func letter(for date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> DayLetter? {
        guard config.kind == .alternatingAB else { return nil }
        guard isLetteredDay(date, config: config, calendar: calendar) else { return nil }

        let all = anchors(config: config, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        // The most recent restart on or before this day, or the first one when
        // the date is earlier than any of them.
        guard let anchor = all.last(where: { calendar.startOfDay(for: $0.date) <= day }) ?? all.first
        else { return nil }

        let index = letteredDayOffset(from: anchor.date, to: date, config: config, calendar: calendar)
        let anchorLetter: DayLetter = anchor.isA ? .a : .b
        let isEven = ((index % 2) + 2) % 2 == 0
        return isEven ? anchorLetter : anchorLetter.other
    }

    /// Signed count of lettered days between two dates. The anchor itself is 0.
    ///
    /// Days set aside for every class are passed over rather than counted, so
    /// an introduction day in the middle of a week does not swap every letter
    /// after it.
    static func letteredDayOffset(
        from anchor: Date,
        to date: Date,
        config: ScheduleConfig,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: anchor)
        let end = calendar.startOfDay(for: date)
        if start == end { return 0 }

        let forward = end > start
        var cursor = forward ? start : end
        let stop = forward ? end : start
        var count = 0

        // Bounded so a wildly stale anchor can never spin forever.
        var guardrail = 0
        while cursor < stop, guardrail < 4000 {
            guardrail += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            if isLetteredDay(cursor, config: config, calendar: calendar) { count += 1 }
        }
        return forward ? count : -count
    }

    // MARK: - Meetings

    /// The classes that meet on a given date, in the order they happen.
    public static func classes<T: ScheduleItem>(
        meetingOn date: Date,
        from classes: [T],
        config: ScheduleConfig,
        calendar: Calendar = .current
    ) -> [T] {
        guard isSchoolDay(date, config: config, calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        let dayLetter = letter(for: date, config: config, calendar: calendar)
        let everyClass = isAllClassDay(date, config: config, calendar: calendar)

        return classes
            .filter { item in
                guard !item.isArchived else { return false }
                // On a day set aside, the timetable does not apply: every class
                // this semester meets, whichever days it usually falls on.
                if !everyClass, item.daysMask & (1 << weekday) == 0 { return false }
                // A class tied to one semester disappears when the other is running.
                if let activeSemester = semester(on: date, config: config, calendar: calendar),
                   item.semester != 0, item.semester != activeSemester { return false }
                if everyClass { return true }
                guard config.kind == .alternatingAB, let dayLetter else { return true }
                switch item.abDesignation {
                case .both: return true
                case .a: return dayLetter == .a
                case .b: return dayLetter == .b
                }
            }
            .sorted(by: ordering)
    }

    /// Time of day first, then period, then name — so a class with no set time still lands sensibly.
    static func ordering<T: ScheduleItem>(_ lhs: T, _ rhs: T) -> Bool {
        switch (lhs.startMinutes, rhs.startMinutes) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        switch (lhs.period, rhs.period) {
        case let (l?, r?) where l != r: return l < r
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Which class is happening right now, and which one is up next today.
    public static func nowAndNext<T: ScheduleItem>(
        at moment: Date,
        from classes: [T],
        config: ScheduleConfig,
        calendar: Calendar = .current
    ) -> (now: T?, next: T?) {
        let todays = self.classes(meetingOn: moment, from: classes, config: config, calendar: calendar)
        let minutes = minutesIntoDay(moment, calendar: calendar)

        let current = todays.first { item in
            guard let start = item.startMinutes, let end = item.endMinutes else { return false }
            return minutes >= start && minutes < end
        }
        let upcoming = todays.first { item in
            guard let start = item.startMinutes else { return false }
            return start > minutes
        }
        return (current, upcoming)
    }

    /// Every school day between two dates, for marking a whole break off at once.
    /// Weekends are skipped: they were never school days to begin with.
    public static func schoolDays(
        from start: Date,
        to end: Date,
        config: ScheduleConfig,
        calendar: Calendar = .current
    ) -> [Date] {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        var days: [Date] = []
        var cursor = first

        for _ in 0..<400 {
            guard cursor <= last else { break }
            let weekday = calendar.component(.weekday, from: cursor)
            if config.schoolDays.contains(weekday) { days.append(cursor) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    public static func minutesIntoDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Combines a day with a minutes-from-midnight time.
    public static func date(_ day: Date, atMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// The next school day on or after `date`, if one exists within the year.
    public static func nextSchoolDay(
        onOrAfter date: Date,
        config: ScheduleConfig,
        calendar: Calendar = .current
    ) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<400 {
            if isSchoolDay(cursor, config: config, calendar: calendar) { return cursor }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }
}

public extension ScheduleItem {
    var timeRangeText: String? {
        guard let startMinutes else { return nil }
        let start = TimeFormatting.text(minutes: startMinutes)
        guard let endMinutes else { return start }
        return "\(start) – \(TimeFormatting.text(minutes: endMinutes))"
    }
}

public enum TimeFormatting {
    public static func text(minutes: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(minute == 0 ? "jmm" : "jmm")
        let date = calendar.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }
}
