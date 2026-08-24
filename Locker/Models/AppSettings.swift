import Foundation
import SwiftUI
import SwiftData

/// Single-row settings record. Fetch with `AppSettings.current(in:)`.
@Model
final class AppSettings {
    var hasCompletedOnboarding: Bool = false

    // Appearance
    var accentHex: String = Theme.Accent.default.hex
    var typeStyleRaw: String = Theme.TypeStyle.default.rawValue
    /// "system", "light" or "dark".
    var appearanceRaw: String = "system"
    /// Class names read before term markers were dropped are tidied once.
    var hasTidiedClassNames: Bool = false
    var studentName: String = ""

    // Schedule
    var scheduleKindRaw: String = ScheduleKind.weekly.rawValue
    var firstDayOfSchool: Date?
    var lastDayOfSchool: Date?
    /// Anchor for A/B day math: this date is an A day (or B day if `abAnchorIsA` is false).
    /// Re-anchoring is how the student fixes drift after a snow day — one tap in Settings.
    var abAnchorDate: Date?
    var abAnchorIsA: Bool = true
    /// Weekdays school is in session. Weekends and off days never get an A/B letter.
    var schoolDaysMask: Int = Weekdays.mask(from: Weekdays.schoolWeek)
    /// Dates with no school. Stored as start-of-day.
    var noSchoolDays: [Date] = []
    /// When the second-semester timetable takes over. Nil means the schedule
    /// never changes, and every class is treated as running all year.
    var secondSemesterStart: Date?
    /// Dates when every class meets and no A/B letter is spent.
    var allClassDates: [Date] = []
    /// Dates the A/B rotation starts over on a named letter.
    var abResets: [ABReset] = []
    /// Weekdays that always work that way — a Friday run differently.
    var allClassWeekdays: [Int] = []

    // Reminders
    var remindersEnabled: Bool = true
    var eveningBeforeEnabled: Bool = true
    /// Minutes from midnight for the evening-before nudge.
    var eveningBeforeMinutes: Int = 19 * 60
    var morningOfEnabled: Bool = true
    var morningOfMinutes: Int = 7 * 60
    var hoursBeforeEnabled: Bool = true
    var hoursBeforeCount: Int = 2
    /// Tests and projects get an extra heads-up this many days out.
    var bigDealLeadDaysEnabled: Bool = true
    var bigDealLeadDays: Int = 3
    var classStartRemindersEnabled: Bool = false
    var classStartLeadMinutes: Int = 10

    // Focus timer
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsBeforeLongBreak: Int = 4
    var focusChimeEnabled: Bool = true

    // Google Classroom
    var googleClientID: String = ""
    var classroomAutoSync: Bool = true
    var classroomLastSyncAt: Date?
    var classroomLastSyncSummary: String = ""
    var classroomConnectedEmail: String = ""

    /// Pages worth checking again — a to-do list, a schedule.
    var savedPages: [SavedPage] = []

    /// Column labellings the student has corrected, reused for the same layout.
    var savedColumnLayouts: [SavedColumnLayout] = []

    // Updates
    var updateRepo: String = ""
    var autoCheckForUpdates: Bool = true
    var lastUpdateCheckAt: Date?

    // Misc UI
    var globalHotkeyEnabled: Bool = true
    var streakBestCount: Int = 0

    init() {}

    var scheduleKind: ScheduleKind {
        get { ScheduleKind(rawValue: scheduleKindRaw) ?? .weekly }
        set { scheduleKindRaw = newValue.rawValue }
    }

    var schoolDays: Set<Int> {
        get { Weekdays.set(from: schoolDaysMask) }
        set { schoolDaysMask = Weekdays.mask(from: newValue) }
    }

    /// Snapshot of everything the pure-Swift domain layer needs, so domain code
    /// never has to import SwiftData.
    var scheduleConfig: ScheduleConfig {
        ScheduleConfig(
            kind: scheduleKind,
            schoolDays: schoolDays,
            abAnchorDate: abAnchorDate,
            abAnchorIsA: abAnchorIsA,
            abResets: abResets,
            noSchoolDays: noSchoolDays,
            allClassDates: allClassDates,
            allClassWeekdays: Set(allClassWeekdays),
            firstDayOfSchool: firstDayOfSchool,
            lastDayOfSchool: lastDayOfSchool,
            secondSemesterStart: secondSemesterStart
        )
    }

    var reminderConfig: ReminderConfig {
        ReminderConfig(
            enabled: remindersEnabled,
            eveningBeforeEnabled: eveningBeforeEnabled,
            eveningBeforeMinutes: eveningBeforeMinutes,
            morningOfEnabled: morningOfEnabled,
            morningOfMinutes: morningOfMinutes,
            hoursBeforeEnabled: hoursBeforeEnabled,
            hoursBeforeCount: hoursBeforeCount,
            bigDealLeadDaysEnabled: bigDealLeadDaysEnabled,
            bigDealLeadDays: bigDealLeadDays
        )
    }

    /// Returns the one settings row, creating it on first launch.
    static func current(in context: ModelContext) -> AppSettings {
        let existing = try? context.fetch(FetchDescriptor<AppSettings>())
        if let first = existing?.first { return first }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    /// The named accent in use, or nil when the colour was picked by hand.
    var namedAccent: Theme.Accent? {
        Theme.Accent.allCases.first { $0.hex.caseInsensitiveCompare(accentHex) == .orderedSame }
    }

    var typeStyle: Theme.TypeStyle {
        get { Theme.TypeStyle(rawValue: typeStyleRaw) ?? .default }
        set { typeStyleRaw = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
