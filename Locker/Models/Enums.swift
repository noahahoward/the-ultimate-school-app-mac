import Foundation

/// A stable identifier for an external system we can import from.
public struct SourceID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let googleClassroom = SourceID("classroom")
    public static let skyward = SourceID("skyward")
}

/// A link between a local record and the same record in an external system.
/// Stored as an array so one class can be linked to several sources at once.
public struct ExternalRef: Codable, Hashable, Sendable {
    public var source: SourceID
    public var externalID: String
    /// Where to open this item in the source's web UI, when known.
    public var url: String?

    public init(source: SourceID, externalID: String, url: String? = nil) {
        self.source = source
        self.externalID = externalID
        self.url = url
    }
}

public enum AssignmentType: String, Codable, CaseIterable, Sendable {
    case homework, reading, quiz, test, project, essay, lab, presentation, other

    public var label: String {
        switch self {
        case .homework: "Homework"
        case .reading: "Reading"
        case .quiz: "Quiz"
        case .test: "Test"
        case .project: "Project"
        case .essay: "Essay"
        case .lab: "Lab"
        case .presentation: "Presentation"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .homework: "pencil.and.list.clipboard"
        case .reading: "book"
        case .quiz: "questionmark.circle"
        case .test: "graduationcap"
        case .project: "hammer"
        case .essay: "doc.text"
        case .lab: "flask"
        case .presentation: "person.wave.2"
        case .other: "circle"
        }
    }

    /// Types that usually deserve extra lead time in reminders.
    public var isBigDeal: Bool { self == .test || self == .project || self == .essay }
}

public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0, normal = 1, high = 2

    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

/// Which day of an alternating block schedule a class meets on.
public enum ABDesignation: String, Codable, CaseIterable, Sendable {
    case both, a, b

    public var label: String {
        switch self {
        case .both: "Every day"
        case .a: "A days"
        case .b: "B days"
        }
    }
}

public enum ScheduleKind: String, Codable, CaseIterable, Sendable {
    case weekly, alternatingAB

    public var label: String {
        switch self {
        case .weekly: "Same every week"
        case .alternatingAB: "A / B alternating days"
        }
    }
}

public enum GradingMode: String, Codable, CaseIterable, Sendable {
    case weightedCategories, totalPoints

    public var label: String {
        switch self {
        case .weightedCategories: "Weighted categories"
        case .totalPoints: "Total points"
        }
    }
}

public enum ReviewRating: Int, Codable, CaseIterable, Sendable {
    case again = 0, hard = 1, good = 2, easy = 3

    public var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

public enum FocusPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak
}
