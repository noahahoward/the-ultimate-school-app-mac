import Foundation
@testable import Locker

/// A fixed, timezone-stable calendar so date math in tests never depends on where it runs.
enum TestClock {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// Builds a date in the test calendar. `date(2026, 9, 3, 15, 30)`
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }
}

/// Plain-struct stand-in for `SchoolClass` so schedule tests need no database.
struct TestClass: ScheduleItem {
    var name: String
    var daysMask: Int
    var abDesignation: ABDesignation = .both
    var startMinutes: Int?
    var endMinutes: Int?
    var period: Int?
    var isArchived: Bool = false
    var semester: Int = 0

    init(
        _ name: String,
        days: Set<Int> = Weekdays.schoolWeek,
        ab: ABDesignation = .both,
        start: Int? = nil,
        end: Int? = nil,
        period: Int? = nil,
        archived: Bool = false,
        semester: Int = 0
    ) {
        self.name = name
        self.daysMask = Weekdays.mask(from: days)
        self.abDesignation = ab
        self.startMinutes = start
        self.endMinutes = end
        self.period = period
        self.isArchived = archived
        self.semester = semester
    }
}
