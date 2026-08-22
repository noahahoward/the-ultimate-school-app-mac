import Foundation

/// Everything the schedule math needs, lifted out of SwiftData so it can be tested directly.
public struct ScheduleConfig: Equatable, Sendable {
    public var kind: ScheduleKind
    public var schoolDays: Set<Int>
    public var abAnchorDate: Date?
    public var abAnchorIsA: Bool
    public var noSchoolDays: [Date]
    public var firstDayOfSchool: Date?
    public var lastDayOfSchool: Date?
    public var secondSemesterStart: Date?

    public init(
        kind: ScheduleKind = .weekly,
        schoolDays: Set<Int> = Weekdays.schoolWeek,
        abAnchorDate: Date? = nil,
        abAnchorIsA: Bool = true,
        noSchoolDays: [Date] = [],
        firstDayOfSchool: Date? = nil,
        lastDayOfSchool: Date? = nil,
        secondSemesterStart: Date? = nil
    ) {
        self.kind = kind
        self.schoolDays = schoolDays
        self.abAnchorDate = abAnchorDate
        self.abAnchorIsA = abAnchorIsA
        self.noSchoolDays = noSchoolDays
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

    public static func letter(for date: Date, config: ScheduleConfig, calendar: Calendar = .current) -> DayLetter? {
        guard config.kind == .alternatingAB else { return nil }
        guard let anchor = config.abAnchorDate else { return nil }
        guard isSchoolDay(date, config: config, calendar: calendar) else { return nil }

        let index = schoolDayOffset(from: anchor, to: date, config: config, calendar: calendar)
        let anchorLetter: DayLetter = config.abAnchorIsA ? .a : .b
        let isEven = ((index % 2) + 2) % 2 == 0
        return isEven ? anchorLetter : anchorLetter.other
    }

    /// Signed count of school days between two dates. The anchor day itself is 0.
    /// Walks day by day, which keeps holidays and custom school-day sets exact.
    static func schoolDayOffset(
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
            if isSchoolDay(cursor, config: config, calendar: calendar) { count += 1 }
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

        return classes
            .filter { item in
                guard !item.isArchived else { return false }
                guard item.daysMask & (1 << weekday) != 0 else { return false }
                // A class tied to one semester disappears when the other is running.
                if let activeSemester = semester(on: date, config: config, calendar: calendar),
                   item.semester != 0, item.semester != activeSemester { return false }
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
