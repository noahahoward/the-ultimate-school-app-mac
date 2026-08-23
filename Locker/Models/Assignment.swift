import Foundation
import SwiftData

@Model
final class Assignment {
    var title: String = ""
    var notes: String = ""

    /// Full due date *and* time. `hasDueTime` says whether the time is meaningful
    /// or was defaulted (Google Classroom often gives a date with no time).
    var dueAt: Date?
    var hasDueTime: Bool = false

    var typeRaw: String = AssignmentType.homework.rawValue
    var priorityRaw: Int = Priority.normal.rawValue
    var estimatedMinutes: Int?

    var isDone: Bool = false
    var completedAt: Date?

    /// Something to consult rather than something to hand in — a practice site,
    /// a syllabus, a reading list. It is never due, never late, and never
    /// counted among the work outstanding.
    var isResource: Bool = false

    // Grading
    var score: Double?
    var maxScore: Double?

    // Reminder override; when nil the global settings apply.
    var reminderOffsetsMinutes: [Int]?
    var remindersSuppressed: Bool = false

    // Sync bookkeeping
    var externalRefs: [ExternalRef] = []
    /// Set when the item vanished from its source. We flag rather than delete so
    /// nothing the student wrote is ever silently lost.
    var isMissingFromSource: Bool = false
    var lastSyncedAt: Date?

    var createdAt: Date = Date()

    var schoolClass: SchoolClass?
    var gradeCategory: GradeCategory?

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.assignment)
    var focusSessions: [FocusSession] = []

    init(
        title: String,
        schoolClass: SchoolClass? = nil,
        dueAt: Date? = nil,
        hasDueTime: Bool = false,
        type: AssignmentType = .homework,
        priority: Priority = .normal,
        notes: String = "",
        estimatedMinutes: Int? = nil
    ) {
        self.title = title
        self.schoolClass = schoolClass
        self.dueAt = dueAt
        self.hasDueTime = hasDueTime
        self.typeRaw = type.rawValue
        self.priorityRaw = priority.rawValue
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.createdAt = Date()
    }

    var type: AssignmentType {
        get { AssignmentType(rawValue: typeRaw) ?? .homework }
        set { typeRaw = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    func ref(for source: SourceID) -> ExternalRef? {
        externalRefs.first { $0.source == source }
    }

    var isLinked: Bool { !externalRefs.isEmpty }

    var percentScore: Double? {
        guard let score, let maxScore, maxScore > 0 else { return nil }
        return score / maxScore * 100
    }

    /// Marks done/undone and stamps the completion time, which the streak counter reads.
    func setDone(_ done: Bool, now: Date = Date()) {
        isDone = done
        completedAt = done ? now : nil
    }
}
