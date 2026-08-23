import Foundation
import SwiftData

public struct SyncReport: Equatable, Sendable {
    public var classesCreated = 0
    public var classesLinked = 0
    public var assignmentsCreated = 0
    public var assignmentsUpdated = 0
    public var assignmentsCompleted = 0
    public var assignmentsFlaggedMissing = 0

    public var isEmpty: Bool {
        classesCreated == 0 && classesLinked == 0 && assignmentsCreated == 0
            && assignmentsUpdated == 0 && assignmentsCompleted == 0 && assignmentsFlaggedMissing == 0
    }

    public var summary: String {
        guard !isEmpty else { return "Already up to date" }
        var parts: [String] = []
        if classesCreated > 0 { parts.append("\(classesCreated) new class\(classesCreated == 1 ? "" : "es")") }
        if classesLinked > 0 { parts.append("\(classesLinked) class\(classesLinked == 1 ? "" : "es") linked") }
        if assignmentsCreated > 0 { parts.append("\(assignmentsCreated) new") }
        if assignmentsUpdated > 0 { parts.append("\(assignmentsUpdated) updated") }
        if assignmentsCompleted > 0 { parts.append("\(assignmentsCompleted) marked done") }
        if assignmentsFlaggedMissing > 0 { parts.append("\(assignmentsFlaggedMissing) removed upstream") }
        return parts.joined(separator: ", ")
    }
}

/// Folds imported data into the local store.
///
/// The rule that governs everything here: the source owns the facts it published
/// (title, due date, points), the student owns everything they added (notes,
/// priority, estimates, reminders). Nothing the student typed is ever overwritten,
/// and nothing is deleted — items that vanish upstream get flagged instead.
public enum SyncMerger {

    @discardableResult
    public static func merge(
        _ payload: ImportPayload,
        from source: SourceID,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> SyncReport {
        var report = SyncReport()

        let existingClasses = try context.fetch(FetchDescriptor<SchoolClass>())
        let existingAssignments = try context.fetch(FetchDescriptor<Assignment>())

        var classByExternalID: [String: SchoolClass] = [:]
        for schoolClass in existingClasses {
            if let ref = schoolClass.ref(for: source) { classByExternalID[ref.externalID] = schoolClass }
        }

        // MARK: Classes

        for imported in payload.classes {
            if let existing = classByExternalID[imported.externalID] {
                update(existing, from: imported, source: source)
                continue
            }

            // Adopt a class the student already made by hand rather than creating a duplicate.
            if let match = existingClasses.first(where: {
                $0.ref(for: source) == nil && namesMatch($0.name, imported.name)
            }) {
                match.externalRefs.append(ExternalRef(source: source, externalID: imported.externalID, url: imported.url))
                update(match, from: imported, source: source)
                classByExternalID[imported.externalID] = match
                report.classesLinked += 1
                continue
            }

            let created = SchoolClass(
                name: imported.name,
                teacher: imported.teacher,
                room: imported.room,
                period: imported.period,
                colorHex: ClassPalette.hex(forIndex: existingClasses.count + report.classesCreated),
                daysMask: imported.meetingWeekdays.map(Weekdays.mask(from:)) ?? 0,
                startMinutes: imported.startMinutes,
                endMinutes: imported.endMinutes,
                sortIndex: existingClasses.count + report.classesCreated
            )
            created.externalRefs = [ExternalRef(source: source, externalID: imported.externalID, url: imported.url)]
            context.insert(created)
            classByExternalID[imported.externalID] = created
            report.classesCreated += 1
        }

        // MARK: Assignments

        var assignmentByExternalID: [String: Assignment] = [:]
        for assignment in existingAssignments {
            if let ref = assignment.ref(for: source) { assignmentByExternalID[ref.externalID] = assignment }
        }

        for imported in payload.assignments {
            let owningClass = classByExternalID[imported.classExternalID]

            if let existing = assignmentByExternalID[imported.externalID] {
                let changed = update(existing, from: imported, owningClass: owningClass, source: source, now: now)
                if changed.updated { report.assignmentsUpdated += 1 }
                if changed.completed { report.assignmentsCompleted += 1 }
                continue
            }

            let created = Assignment(
                title: imported.title,
                schoolClass: owningClass,
                dueAt: imported.dueAt,
                hasDueTime: imported.hasDueTime,
                type: imported.type
            )
            created.notes = imported.details
            created.maxScore = imported.maxPoints
            created.externalRefs = [ExternalRef(source: source, externalID: imported.externalID, url: imported.url)]
            created.lastSyncedAt = now
            if imported.isSubmitted == true { created.setDone(true, now: now) }
            context.insert(created)
            assignmentByExternalID[imported.externalID] = created
            report.assignmentsCreated += 1
        }

        // MARK: Items that disappeared upstream

        let seenIDs = Set(payload.assignments.map(\.externalID))
        for (externalID, assignment) in assignmentByExternalID where !seenIDs.contains(externalID) {
            if !assignment.isMissingFromSource {
                assignment.isMissingFromSource = true
                report.assignmentsFlaggedMissing += 1
            }
        }

        try context.save()
        return report
    }

    // MARK: - Field-level rules

    private static func update(_ schoolClass: SchoolClass, from imported: ImportedClass, source: SourceID) {
        // The name is deliberately left alone after the first import: students
        // rename "Biology I - Sec 3 - Smith" to "Bio" and shouldn't lose that.
        if schoolClass.teacher.isEmpty { schoolClass.teacher = imported.teacher }
        if schoolClass.room.isEmpty { schoolClass.room = imported.room }
        if schoolClass.period == nil { schoolClass.period = imported.period }
        if schoolClass.daysMask == 0, let weekdays = imported.meetingWeekdays {
            schoolClass.daysMask = Weekdays.mask(from: weekdays)
        }
        if schoolClass.startMinutes == nil { schoolClass.startMinutes = imported.startMinutes }
        if schoolClass.endMinutes == nil { schoolClass.endMinutes = imported.endMinutes }

        if let index = schoolClass.externalRefs.firstIndex(where: { $0.source == source }) {
            schoolClass.externalRefs[index].url = imported.url ?? schoolClass.externalRefs[index].url
        }
    }

    private static func update(
        _ assignment: Assignment,
        from imported: ImportedAssignment,
        owningClass: SchoolClass?,
        source: SourceID,
        now: Date
    ) -> (updated: Bool, completed: Bool) {
        var updated = false
        var completed = false

        if assignment.title != imported.title {
            assignment.title = imported.title
            updated = true
        }
        // A fetch that omits the due date must not erase one already known: the
        // source dropping a field is far likelier than the deadline vanishing,
        // and a due date silently becoming nil is invisible until it's missed.
        if imported.dueAt != nil || assignment.dueAt == nil {
            if assignment.dueAt != imported.dueAt || assignment.hasDueTime != imported.hasDueTime {
                assignment.dueAt = imported.dueAt
                assignment.hasDueTime = imported.hasDueTime
                updated = true
            }
        }
        if let points = imported.maxPoints, assignment.maxScore != points {
            assignment.maxScore = points
            updated = true
        }
        if assignment.schoolClass == nil, let owningClass {
            assignment.schoolClass = owningClass
            updated = true
        }
        // Submitting upstream completes it here. Un-submitting does not un-complete
        // it — the student may have finished on paper.
        if imported.isSubmitted == true, !assignment.isDone {
            assignment.setDone(true, now: now)
            completed = true
        }
        if assignment.isMissingFromSource {
            assignment.isMissingFromSource = false
            updated = true
        }

        assignment.lastSyncedAt = now
        return (updated, completed)
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ value: String) -> String {
            value.lowercased()
                .filter { $0.isLetter || $0.isNumber }
        }
        let a = key(lhs), b = key(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }
}
