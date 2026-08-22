import Foundation

public struct ReminderConfig: Equatable, Sendable {
    public var enabled: Bool
    public var eveningBeforeEnabled: Bool
    public var eveningBeforeMinutes: Int
    public var morningOfEnabled: Bool
    public var morningOfMinutes: Int
    public var hoursBeforeEnabled: Bool
    public var hoursBeforeCount: Int
    public var bigDealLeadDaysEnabled: Bool
    public var bigDealLeadDays: Int

    public init(
        enabled: Bool = true,
        eveningBeforeEnabled: Bool = true,
        eveningBeforeMinutes: Int = 19 * 60,
        morningOfEnabled: Bool = true,
        morningOfMinutes: Int = 7 * 60,
        hoursBeforeEnabled: Bool = true,
        hoursBeforeCount: Int = 2,
        bigDealLeadDaysEnabled: Bool = true,
        bigDealLeadDays: Int = 3
    ) {
        self.enabled = enabled
        self.eveningBeforeEnabled = eveningBeforeEnabled
        self.eveningBeforeMinutes = eveningBeforeMinutes
        self.morningOfEnabled = morningOfEnabled
        self.morningOfMinutes = morningOfMinutes
        self.hoursBeforeEnabled = hoursBeforeEnabled
        self.hoursBeforeCount = hoursBeforeCount
        self.bigDealLeadDaysEnabled = bigDealLeadDaysEnabled
        self.bigDealLeadDays = bigDealLeadDays
    }
}

public enum ReminderKind: String, Sendable {
    case eveningBefore, morningOf, hoursBefore, bigDealLead

    public var label: String {
        switch self {
        case .eveningBefore: "Tonight"
        case .morningOf: "This morning"
        case .hoursBefore: "Coming up"
        case .bigDealLead: "Heads up"
        }
    }
}

public struct ReminderPlan: Equatable, Sendable {
    public var fireAt: Date
    public var kind: ReminderKind

    public init(fireAt: Date, kind: ReminderKind) {
        self.fireAt = fireAt
        self.kind = kind
    }
}

/// What the assignment contributes to reminder timing.
public struct ReminderSubject: Equatable, Sendable {
    public var dueAt: Date
    public var hasDueTime: Bool
    public var type: AssignmentType
    public var isDone: Bool
    public var suppressed: Bool
    /// Overrides the global rules with plain "minutes before due" offsets.
    public var customOffsetsMinutes: [Int]?

    public init(
        dueAt: Date,
        hasDueTime: Bool,
        type: AssignmentType,
        isDone: Bool = false,
        suppressed: Bool = false,
        customOffsetsMinutes: [Int]? = nil
    ) {
        self.dueAt = dueAt
        self.hasDueTime = hasDueTime
        self.type = type
        self.isDone = isDone
        self.suppressed = suppressed
        self.customOffsetsMinutes = customOffsetsMinutes
    }
}

public enum ReminderScheduler {

    /// Fire times for one assignment, already filtered to the future and de-duplicated.
    public static func plans(
        for subject: ReminderSubject,
        config: ReminderConfig,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReminderPlan] {
        guard config.enabled, !subject.isDone, !subject.suppressed else { return [] }

        if let offsets = subject.customOffsetsMinutes {
            return offsets
                .map { ReminderPlan(fireAt: subject.dueAt.addingTimeInterval(Double(-$0) * 60), kind: .hoursBefore) }
                .filter { $0.fireAt > now }
                .sorted { $0.fireAt < $1.fireAt }
        }

        var plans: [ReminderPlan] = []
        let dueDay = calendar.startOfDay(for: subject.dueAt)
        // An all-day assignment is really due by the end of that day, so a
        // morning-of nudge is still in time even though it is after midnight.
        let deadline = subject.hasDueTime
            ? subject.dueAt
            : ScheduleEngine.date(dueDay, atMinutes: 23 * 60 + 59, calendar: calendar)

        if config.eveningBeforeEnabled,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDay) {
            plans.append(ReminderPlan(
                fireAt: ScheduleEngine.date(dayBefore, atMinutes: config.eveningBeforeMinutes, calendar: calendar),
                kind: .eveningBefore
            ))
        }

        if config.morningOfEnabled {
            plans.append(ReminderPlan(
                fireAt: ScheduleEngine.date(dueDay, atMinutes: config.morningOfMinutes, calendar: calendar),
                kind: .morningOf
            ))
        }

        // "2 hours before" only means something when a real time was given.
        // Without one the due time is a placeholder, so the day-based nudges carry it.
        if config.hoursBeforeEnabled, subject.hasDueTime, config.hoursBeforeCount > 0 {
            plans.append(ReminderPlan(
                fireAt: subject.dueAt.addingTimeInterval(Double(-config.hoursBeforeCount) * 3600),
                kind: .hoursBefore
            ))
        }

        if config.bigDealLeadDaysEnabled, subject.type.isBigDeal, config.bigDealLeadDays > 0,
           let leadDay = calendar.date(byAdding: .day, value: -config.bigDealLeadDays, to: dueDay) {
            plans.append(ReminderPlan(
                fireAt: ScheduleEngine.date(leadDay, atMinutes: config.eveningBeforeMinutes, calendar: calendar),
                kind: .bigDealLead
            ))
        }

        var seen = Set<Date>()
        return plans
            .filter { $0.fireAt > now && $0.fireAt <= deadline.addingTimeInterval(60) }
            .filter { seen.insert($0.fireAt).inserted }
            .sorted { $0.fireAt < $1.fireAt }
    }
}
