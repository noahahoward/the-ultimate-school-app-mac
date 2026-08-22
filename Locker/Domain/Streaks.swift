import Foundation

public struct StreakSummary: Equatable, Sendable {
    public var current: Int
    public var best: Int
    /// True once something has been finished today, which is what the UI celebrates.
    public var didSomethingToday: Bool

    public init(current: Int, best: Int, didSomethingToday: Bool) {
        self.current = current
        self.best = best
        self.didSomethingToday = didSomethingToday
    }
}

/// Counts consecutive *school* days with at least one completed assignment.
///
/// Weekends and holidays never break a streak — nobody should lose a streak for
/// not doing homework on Thanksgiving.
public enum Streaks {

    public static func summary(
        completionDates: [Date],
        config: ScheduleConfig,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StreakSummary {
        let days = Set(completionDates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        let didToday = days.contains(today)

        var current = 0
        var cursor = today

        // Today not being done yet shouldn't zero out a live streak — start
        // counting from yesterday in that case.
        if !didToday {
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        for _ in 0..<400 {
            if !ScheduleEngine.isSchoolDay(cursor, config: config, calendar: calendar) {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }
            guard days.contains(cursor) else { break }
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return StreakSummary(current: current, best: max(current, longest(days: days, config: config, calendar: calendar)), didSomethingToday: didToday)
    }

    static func longest(days: Set<Date>, config: ScheduleConfig, calendar: Calendar) -> Int {
        guard let earliest = days.min(), let latest = days.max() else { return 0 }
        var best = 0
        var run = 0
        var cursor = earliest

        for _ in 0..<800 {
            guard cursor <= latest else { break }
            if ScheduleEngine.isSchoolDay(cursor, config: config, calendar: calendar) {
                if days.contains(cursor) {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return best
    }
}
