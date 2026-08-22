import Foundation

extension SchoolClass: ScheduleItem {}

extension SchoolClass {
    /// The shape the quick-add parser matches against.
    var classRef: ClassRef {
        ClassRef(id: idString, name: name, aliases: aliases, startMinutes: startMinutes)
    }

    /// A stable string key for a SwiftData object, used wherever the domain layer
    /// needs an identity but must not know about persistence.
    var idString: String { String(describing: persistentModelID) }
}

extension Assignment {
    var idString: String { String(describing: persistentModelID) }

    var reminderSubject: ReminderSubject? {
        guard let dueAt else { return nil }
        return ReminderSubject(
            dueAt: dueAt,
            hasDueTime: hasDueTime,
            type: type,
            isDone: isDone,
            suppressed: remindersSuppressed,
            customOffsetsMinutes: reminderOffsetsMinutes
        )
    }
}

extension GradeCategory {
    var idString: String { String(describing: persistentModelID) }

    var def: CategoryDef { CategoryDef(id: idString, name: name, weight: weight) }
}
