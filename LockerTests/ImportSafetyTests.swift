import XCTest
import SwiftData
@testable import Locker

/// Cases where a wrong answer is worse than no answer.
final class ImportSafetyTests: XCTestCase {

    let calendar = TestClock.calendar
    lazy var now = TestClock.date(2026, 8, 22, 12, 0)

    // MARK: - Status

    func testNegatedStatusesAreNotReadAsTurnedIn() {
        // Every one of these contains the word it negates, so a positive-first
        // check marks unfinished work as done.
        for label in ["Not Submitted", "Not Turned In", "Not Done", "Incomplete",
                      "Unsubmitted", "No Submission", "Missing", "Past Due"] {
            XCTAssertEqual(FieldParsing.isTurnedIn(from: label), false, "“\(label)” means it is not done")
        }
    }

    func testGenuinelyFinishedStatusesStillRead() {
        for label in ["Turned in", "Handed in", "Submitted", "Returned", "Done", "Complete"] {
            XCTAssertEqual(FieldParsing.isTurnedIn(from: label), true, "“\(label)” means it is done")
        }
    }

    func testUnknownStatusesLeaveTheAssignmentAlone() {
        XCTAssertNil(FieldParsing.isTurnedIn(from: "Graded"))
        XCTAssertNil(FieldParsing.isTurnedIn(from: ""))
    }

    // MARK: - Impossible dates

    func testADateThatDoesNotExistIsRejectedRatherThanRolledForward() {
        // Calendar quietly turns 31 September into 1 October.
        XCTAssertNil(FieldParsing.date(from: "Sept 31, 2026", now: now, calendar: calendar))
        XCTAssertNil(FieldParsing.date(from: "Feb 30, 2026", now: now, calendar: calendar))
        XCTAssertNil(FieldParsing.date(from: "2/30", now: now, calendar: calendar))
    }

    func testRealDatesStillParse() {
        XCTAssertEqual(FieldParsing.date(from: "Sept 30, 2026", now: now, calendar: calendar),
                       TestClock.date(2026, 9, 30))
        XCTAssertEqual(FieldParsing.date(from: "Feb 29, 2028", now: now, calendar: calendar),
                       TestClock.date(2028, 2, 29), "2028 is a leap year")
    }

    // MARK: - Room codes

    func testARoomCodeIsNotReadAsAPeriod() {
        // Portable classrooms are labelled P1...P12 in plenty of schools.
        XCTAssertNil(ScheduleParsing.period(in: "Rm P12"))
        XCTAssertNil(ScheduleParsing.period(in: "Bldg S2"), "that is a building, not a semester")
        XCTAssertNil(ScheduleParsing.semester(in: "Bldg S2"))
    }

    func testRealPeriodsAndSemestersStillParse() {
        XCTAssertEqual(ScheduleParsing.period(in: "Period 3 - SEMESTER 1"), 3)
        XCTAssertEqual(ScheduleParsing.period(in: "P4"), 4)
        XCTAssertEqual(ScheduleParsing.semester(in: "Period 1 - SEMESTER 2"), 2)
        XCTAssertEqual(ScheduleParsing.semester(in: "S1"), 1)
    }

    // MARK: - Sync

    func testASyncThatOmitsTheDueDateDoesNotEraseIt() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let source = SourceID.googleClassroom
        let due = TestClock.date(2026, 9, 18)

        try SyncMerger.merge(
            ImportPayload(assignments: [
                ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay", dueAt: due)
            ]),
            from: source, into: context, now: now
        )

        // The same item comes back without a due date, as a flaky fetch can.
        try SyncMerger.merge(
            ImportPayload(assignments: [
                ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay", dueAt: nil)
            ]),
            from: source, into: context, now: now
        )

        let assignment = try XCTUnwrap(context.fetch(FetchDescriptor<Assignment>()).first)
        XCTAssertEqual(assignment.dueAt, due, "a deadline must not disappear because a fetch omitted it")
    }

    func testAGenuinelyChangedDueDateStillUpdates() throws {
        let container = try ModelContainer(
            for: Persistence.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let source = SourceID.googleClassroom

        try SyncMerger.merge(
            ImportPayload(assignments: [
                ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay",
                                   dueAt: TestClock.date(2026, 9, 18))
            ]),
            from: source, into: context, now: now
        )
        try SyncMerger.merge(
            ImportPayload(assignments: [
                ImportedAssignment(externalID: "a1", classExternalID: "c1", title: "Essay",
                                   dueAt: TestClock.date(2026, 9, 25))
            ]),
            from: source, into: context, now: now
        )

        let assignment = try XCTUnwrap(context.fetch(FetchDescriptor<Assignment>()).first)
        XCTAssertEqual(assignment.dueAt, TestClock.date(2026, 9, 25))
    }
}
