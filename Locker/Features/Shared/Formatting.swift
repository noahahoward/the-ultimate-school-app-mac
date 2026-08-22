import Foundation
import SwiftUI

enum DueFormat {

    enum Urgency {
        case overdue, today, tomorrow, soon, later, none

        var color: Color {
            switch self {
            case .overdue: Theme.overdue
            case .today: Theme.highlighterDeep
            case .tomorrow: .primary
            case .soon, .later, .none: .secondary
            }
        }
    }

    static func urgency(for dueAt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Urgency {
        guard let dueAt else { return .none }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueAt)

        if dueAt < now && dueDay < today { return .overdue }
        if dueDay < today { return .overdue }
        if dueDay == today { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), dueDay == tomorrow { return .tomorrow }
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        return days <= 7 ? .soon : .later
    }

    /// Short, human phrasing: "Today 3:00 PM", "Fri", "Sep 18", "2 days late".
    static func text(for dueAt: Date?, hasTime: Bool, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let dueAt else { return "No due date" }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueAt)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

        let time = hasTime ? " " + timeText(dueAt) : ""

        switch days {
        case 0: return "Today" + time
        case 1: return "Tomorrow" + time
        case -1: return "Yesterday"
        case ..<(-1): return "\(-days) days late"
        case 2...6:
            let weekday = DateFormatter()
            weekday.dateFormat = "EEE"
            return weekday.string(from: dueAt) + time
        default:
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: dueAt)
        }
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date)
    }

    static func minutesText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }
}
