import XCTest
import SwiftData
@testable import Locker

final class SyncMergerTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    let source = SourceID.googleClassroom
    let now = TestClock.date(2026, 9, 3, 12, 0)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: SchoolClass.self, Assignment.self, AppSettings.self, Deck.self, Card.self,
            ReviewLog.self, FocusSession.self, GradeCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func classes() throws -> [SchoolClass] {
        try context.fetch(FetchDescriptor<SchoolClass>())
    }

    func assignments() throws -> [Assignment] {
        try context.fetch(FetchDescriptor<Assignment>())
    }

    func payload(
        classes: [ImportedClass] = [],
        assignments: [ImportedAssignment] = []
    ) -> ImportPayload {
        ImportPayload(classes: classes, assignments: assignments)
    }

    // MARK: - Creating

    func testCreatesClassesAndAssignments() throws {
        let report = try SyncMerger.merge(
            payload(
                classes: [ImportedClass(externalID: "c1", name: "Biology I", teacher: "Ms. Reyes", room: "204")],
                assignments: [ImportedAssignment(
                    externalID: "a1", classExternalID: "c1", title: "Cell diagram",
                    dueAt: TestClock.date(2026, 9, 5), type: .homework
                )]
            ),
            from: source, into: context, now: now
        )

        XCTAssertEqual(report.classesCreated, 1)
        XCTAssertEqual(report.assignmentsCreated, 1)

        let created = try XCTUnwrap(classes().first)
        XCTAssertEqual(created.name, "Biology I")
        XCTAssertEqual(created.teacher, "Ms. Reyes")
        XCTAssertEqual(created.ref(for: source)?.externalID, "c1")

        let assignment = try XCTUnwrap(assignments().first)
        XCTAssertEqual(assignment.title, "Cell diagram")
        XCTAssertEqual(assignment.schoolClass?.name, "Biology I")
    }

    func testSecondSyncIsIdempotent() throws {
        let input = payload(
            classes: [ImportedClass(externalID: "c1", name: "Biology I")],
            assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Cell diagram")]
        )
        try SyncMerger.merge(input, from: source, into: context, now: now)
        let second = try SyncMerger.merge(input, from: source, into: context, now: now)

        XCTAssertEqual(try classes().count, 1)
        XCTAssertEqual(try assignments().count, 1)
        XCTAssertEqual(second.assignmentsCreated, 0)
        XCTAssertEqual(second.classesCreated, 0)
    }

    // MARK: - Linking to hand-made classes

    func testLinksToAnExistingHandMadeClassInsteadOfDuplicating() throws {
        let manual = SchoolClass(name: "Biology", daysMask: Weekdays.mask(from: [2, 4]), startMinutes: 8 * 60)
        context.insert(manual)
        try context.save()

        let report = try SyncMerger.merge(
            payload(classes: [ImportedClass(externalID: "c1", name: "Biology I", teacher: "Ms. Reyes")]),
            from: source, into: context, now: now
        )

        XCTAssertEqual(report.classesLinked, 1)
        XCTAssertEqual(report.classesCreated, 0)
        XCTAssertEqual(try classes().count, 1)

        let linked = try XCTUnwrap(classes().first)
        XCTAssertEqual(linked.ref(for: source)?.externalID, "c1")
        XCTAssertEqual(linked.teacher, "Ms. Reyes")
        // The hand-entered schedule survives the link.
        XCTAssertEqual(linked.startMinutes, 8 * 60)
        XCTAssertEqual(linked.meetingDays, [2, 4])
    }

    func testLocalRenameSurvivesResync() throws {
        try SyncMerger.merge(
            payload(classes: [ImportedClass(externalID: "c1", name: "Biology I - Sec 3 - Reyes")]),
            from: source, into: context, now: now
        )
        let schoolClass = try XCTUnwrap(classes().first)
        schoolClass.name = "Bio"
        try context.save()

        try SyncMerger.merge(
            payload(classes: [ImportedClass(externalID: "c1", name: "Biology I - Sec 3 - Reyes")]),
            from: source, into: context, now: now
        )
        XCTAssertEqual(try XCTUnwrap(classes().first).name, "Bio")
    }

    // MARK: - Updating

    func testRemoteOwnedFieldsUpdate() throws {
        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(
                externalID: "a1", classExternalID: "c1", title: "Draft",
                dueAt: TestClock.date(2026, 9, 5)
            )]),
            from: source, into: context, now: now
        )

        let report = try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(
                externalID: "a1", classExternalID: "c1", title: "Final draft",
                dueAt: TestClock.date(2026, 9, 8, 15, 0), hasDueTime: true, maxPoints: 50
            )]),
            from: source, into: context, now: now
        )

        let assignment = try XCTUnwrap(assignments().first)
        XCTAssertEqual(report.assignmentsUpdated, 1)
        XCTAssertEqual(assignment.title, "Final draft")
        XCTAssertEqual(assignment.dueAt, TestClock.date(2026, 9, 8, 15, 0))
        XCTAssertTrue(assignment.hasDueTime)
        XCTAssertEqual(assignment.maxScore, 50)
    }

    func testStudentOwnedFieldsAreNeverOverwritten() throws {
        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay")]),
            from: source, into: context, now: now
        )

        let assignment = try XCTUnwrap(assignments().first)
        assignment.notes = "Use the outline from Tuesday"
        assignment.priority = .high
        assignment.estimatedMinutes = 90
        assignment.reminderOffsetsMinutes = [60]
        try context.save()

        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(
                externalID: "a1", classExternalID: "c1", title: "Essay", details: "Upstream description changed"
            )]),
            from: source, into: context, now: now
        )

        let after = try XCTUnwrap(assignments().first)
        XCTAssertEqual(after.notes, "Use the outline from Tuesday")
        XCTAssertEqual(after.priority, .high)
        XCTAssertEqual(after.estimatedMinutes, 90)
        XCTAssertEqual(after.reminderOffsetsMinutes, [60])
    }

    // MARK: - Completion

    func testSubmittedUpstreamMarksItDone() throws {
        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay")]),
            from: source, into: context, now: now
        )
        let report = try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(
                externalID: "a1", classExternalID: "c1", title: "Essay", isSubmitted: true
            )]),
            from: source, into: context, now: now
        )

        XCTAssertEqual(report.assignmentsCompleted, 1)
        XCTAssertTrue(try XCTUnwrap(assignments().first).isDone)
    }

    func testLocallyCompletedWorkIsNotReopenedByTheSource() throws {
        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay")]),
            from: source, into: context, now: now
        )
        let assignment = try XCTUnwrap(assignments().first)
        assignment.setDone(true, now: now)
        try context.save()

        try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(
                externalID: "a1", classExternalID: "c1", title: "Essay", isSubmitted: false
            )]),
            from: source, into: context, now: now
        )
        XCTAssertTrue(try XCTUnwrap(assignments().first).isDone)
    }

    // MARK: - Disappearing upstream

    func testMissingAssignmentsAreFlaggedNotDeleted() throws {
        try SyncMerger.merge(
            payload(assignments: [
                ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Kept"),
                ImportedAssignment(externalID: "a2", classExternalID: "c1", title: "Removed upstream"),
            ]),
            from: source, into: context, now: now
        )

        let report = try SyncMerger.merge(
            payload(assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Kept")]),
            from: source, into: context, now: now
        )

        XCTAssertEqual(report.assignmentsFlaggedMissing, 1)
        XCTAssertEqual(try assignments().count, 2)
        let removed = try XCTUnwrap(assignments().first { $0.title == "Removed upstream" })
        XCTAssertTrue(removed.isMissingFromSource)
    }

    func testReappearingAssignmentClearsTheFlag() throws {
        let full = payload(assignments: [ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay")])
        try SyncMerger.merge(full, from: source, into: context, now: now)
        try SyncMerger.merge(payload(), from: source, into: context, now: now)
        XCTAssertTrue(try XCTUnwrap(assignments().first).isMissingFromSource)

        try SyncMerger.merge(full, from: source, into: context, now: now)
        XCTAssertFalse(try XCTUnwrap(assignments().first).isMissingFromSource)
    }

    func testLocallyCreatedItemsAreUntouchedBySync() throws {
        let manual = Assignment(title: "Study for the ACT")
        context.insert(manual)
        try context.save()

        try SyncMerger.merge(payload(), from: source, into: context, now: now)

        let untouched = try XCTUnwrap(assignments().first { $0.title == "Study for the ACT" })
        XCTAssertFalse(untouched.isMissingFromSource)
        XCTAssertTrue(untouched.externalRefs.isEmpty)
    }

    // MARK: - Name matching

    func testNameMatching() {
        XCTAssertTrue(SyncMerger.namesMatch("Biology", "Biology I"))
        XCTAssertTrue(SyncMerger.namesMatch("AP US History", "ap us history"))
        XCTAssertFalse(SyncMerger.namesMatch("Biology", "Chemistry"))
        XCTAssertFalse(SyncMerger.namesMatch("", "Biology"))
    }
}
