import Foundation
import SwiftData

@Model
final class SchoolClass {
    var name: String = ""
    /// Extra names the quick-add parser will recognize, e.g. "bio" for "Biology I".
    var aliases: [String] = []
    var teacher: String = ""
    var room: String = ""
    /// Period number, when the school uses them. Also the sort key for the day view.
    var period: Int?
    var colorHex: String = ClassPalette.defaultHex

    /// Bitmask of `Calendar` weekdays (1 = Sunday ... 7 = Saturday). Bit n set => meets on weekday n.
    var daysMask: Int = 0
    /// Minutes from midnight, e.g. 8*60+15 for 8:15 AM. Nil means "no fixed time".
    var startMinutes: Int?
    var endMinutes: Int?

    var abDesignationRaw: String = ABDesignation.both.rawValue
    var gradingModeRaw: String = GradingMode.weightedCategories.rawValue
    /// Grade the student is aiming for in this class, as a percentage.
    var goalPercent: Double = 90

    var isArchived: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    var externalRefs: [ExternalRef] = []

    @Relationship(deleteRule: .cascade, inverse: \Assignment.schoolClass)
    var assignments: [Assignment] = []

    @Relationship(deleteRule: .cascade, inverse: \GradeCategory.schoolClass)
    var gradeCategories: [GradeCategory] = []

    @Relationship(deleteRule: .nullify, inverse: \Deck.schoolClass)
    var decks: [Deck] = []

    init(
        name: String,
        aliases: [String] = [],
        teacher: String = "",
        room: String = "",
        period: Int? = nil,
        colorHex: String = ClassPalette.defaultHex,
        daysMask: Int = 0,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil,
        abDesignation: ABDesignation = .both,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.aliases = aliases
        self.teacher = teacher
        self.room = room
        self.period = period
        self.colorHex = colorHex
        self.daysMask = daysMask
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.abDesignationRaw = abDesignation.rawValue
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    var abDesignation: ABDesignation {
        get { ABDesignation(rawValue: abDesignationRaw) ?? .both }
        set { abDesignationRaw = newValue.rawValue }
    }

    var gradingMode: GradingMode {
        get { GradingMode(rawValue: gradingModeRaw) ?? .weightedCategories }
        set { gradingModeRaw = newValue.rawValue }
    }

    var meetingDays: Set<Int> {
        get { Weekdays.set(from: daysMask) }
        set { daysMask = Weekdays.mask(from: newValue) }
    }

    func ref(for source: SourceID) -> ExternalRef? {
        externalRefs.first { $0.source == source }
    }

    var isLinked: Bool { !externalRefs.isEmpty }
}

/// Weekday bitmask helpers. Weekday numbers follow `Calendar` (1 = Sunday).
public enum Weekdays {
    public static let schoolWeek: Set<Int> = [2, 3, 4, 5, 6]

    public static func mask(from days: Set<Int>) -> Int {
        days.reduce(0) { $0 | (1 << $1) }
    }

    public static func set(from mask: Int) -> Set<Int> {
        Set((1...7).filter { mask & (1 << $0) != 0 })
    }

    public static func shortName(_ weekday: Int) -> String {
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
    }

    public static func letter(_ weekday: Int) -> String {
        ["", "S", "M", "T", "W", "T", "F", "S"][weekday]
    }
}

enum ClassPalette {
    /// Colors chosen to stay legible on both light and dark backgrounds.
    static let hexes = [
        "FF6B6B", "F7934C", "FFC145", "6BCB77", "4D96FF",
        "9B7EDE", "EC6FB0", "3BC9C9", "A0703A", "6C7A89",
    ]
    static var defaultHex: String { hexes[4] }

    static func hex(forIndex index: Int) -> String {
        hexes[abs(index) % hexes.count]
    }
}
