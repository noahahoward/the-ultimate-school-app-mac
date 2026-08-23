import Foundation

/// Repeat dates for work that comes back every week.
///
/// Deliberately the simplest thing that helps: a weekly reading log or a Monday
/// vocab quiz is the case students actually have, and copies are made once at
/// creation rather than the app growing a recurrence engine to maintain.
public enum Recurrence {

    /// The most copies one assignment can spawn, so a slip of the stepper can't
    /// bury a term in duplicates.
    public static let maximumRepeats = 30

    /// Dates for the repeats *after* the original, one week apart.
    public static func weekly(
        after start: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        let capped = min(count, maximumRepeats)
        return (1...capped).compactMap {
            calendar.date(byAdding: .day, value: 7 * $0, to: start)
        }
    }

    /// Stops repeats running past the end of the school year.
    public static func weekly(
        after start: Date,
        count: Int,
        notLaterThan lastDay: Date?,
        calendar: Calendar = .current
    ) -> [Date] {
        let dates = weekly(after: start, count: count, calendar: calendar)
        guard let lastDay else { return dates }
        let cutoff = calendar.startOfDay(for: lastDay)
        return dates.filter { calendar.startOfDay(for: $0) <= cutoff }
    }
}
