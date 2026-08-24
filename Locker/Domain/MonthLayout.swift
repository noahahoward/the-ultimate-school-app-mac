import Foundation

/// Lays a month out in rows of seven for a calendar grid.
///
/// Pure so it can be checked without drawing anything: the shape of a month is
/// exactly the kind of arithmetic that looks right and is off by a day.
public enum MonthLayout {

    /// The weeks of the month containing `date`: always six rows of seven,
    /// padded with nil outside the month.
    ///
    /// Six because a month needs four to six of them, and a grid that changes
    /// height as you page through the year moves everything below it.
    public static func weeks(of date: Date, calendar: Calendar = .current) -> [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: date),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return [] }

        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in range {
            days.append(calendar.date(byAdding: .day, value: offset - 1, to: first))
        }
        while days.count < 42 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< $0 + 7]) }
    }

    /// Weekday initials starting on whichever day the locale's week starts.
    public static func weekdayInitials(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
