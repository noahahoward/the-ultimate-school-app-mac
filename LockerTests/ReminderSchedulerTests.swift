import XCTest
@testable import Locker

final class ReminderSchedulerTests: XCTestCase {

    let calendar = TestClock.calendar
    lazy var now = TestClock.date(2026, 9, 1, 9, 0)
    let config = ReminderConfig()

    func plans(_ subject: ReminderSubject, config: ReminderConfig? = nil) -> [ReminderPlan] {
        ReminderScheduler.plans(for: subject, config: config ?? self.config, now: now, calendar: calendar)
    }

    func testDatedAssignmentGetsEveningBeforeAndMorningOf() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .homework)
        let kinds = plans(subject).map(\.kind)
        XCTAssertEqual(kinds, [.eveningBefore, .morningOf])
    }

    func testEveningBeforeUsesConfiguredTime() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .homework)
        let evening = plans(subject).first { $0.kind == .eveningBefore }
        XCTAssertEqual(evening?.fireAt, TestClock.date(2026, 9, 3, 19, 0))
    }

    func testHoursBeforeOnlyAppliesWhenATimeWasGiven() {
        let withoutTime = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .homework)
        XCTAssertFalse(plans(withoutTime).contains { $0.kind == .hoursBefore })

        let withTime = ReminderSubject(dueAt: TestClock.date(2026, 9, 4, 15, 0), hasDueTime: true, type: .homework)
        let hoursBefore = plans(withTime).first { $0.kind == .hoursBefore }
        XCTAssertEqual(hoursBefore?.fireAt, TestClock.date(2026, 9, 4, 13, 0))
    }

    func testTestsGetAnExtraHeadsUp() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 10), hasDueTime: false, type: .test)
        let lead = plans(subject).first { $0.kind == .bigDealLead }
        XCTAssertEqual(lead?.fireAt, TestClock.date(2026, 9, 7, 19, 0))
    }

    func testHomeworkDoesNotGetTheExtraHeadsUp() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 10), hasDueTime: false, type: .homework)
        XCTAssertFalse(plans(subject).contains { $0.kind == .bigDealLead })
    }

    func testPastFireTimesAreDropped() {
        // Due today at 5 PM; the evening-before and morning-of times have passed.
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 1, 17, 0), hasDueTime: true, type: .homework)
        let result = plans(subject)
        XCTAssertTrue(result.allSatisfy { $0.fireAt > now })
        XCTAssertEqual(result.map(\.kind), [.hoursBefore])
    }

    func testNothingIsScheduledForCompletedWork() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .test, isDone: true)
        XCTAssertTrue(plans(subject).isEmpty)
    }

    func testSuppressedAssignmentGetsNothing() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .test, suppressed: true)
        XCTAssertTrue(plans(subject).isEmpty)
    }

    func testGlobalToggleOff() {
        var off = config
        off.enabled = false
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 4), hasDueTime: false, type: .homework)
        XCTAssertTrue(plans(subject, config: off).isEmpty)
    }

    func testCustomOffsetsReplaceTheDefaults() {
        let subject = ReminderSubject(
            dueAt: TestClock.date(2026, 9, 4, 12, 0),
            hasDueTime: true,
            type: .homework,
            customOffsetsMinutes: [60, 1440]
        )
        let result = plans(subject)
        XCTAssertEqual(result.map(\.fireAt), [
            TestClock.date(2026, 9, 3, 12, 0),
            TestClock.date(2026, 9, 4, 11, 0),
        ])
    }

    func testPlansAreSortedAndDeduplicated() {
        let subject = ReminderSubject(dueAt: TestClock.date(2026, 9, 15, 20, 0), hasDueTime: true, type: .project)
        let result = plans(subject)
        XCTAssertEqual(result.map(\.fireAt), result.map(\.fireAt).sorted())
        XCTAssertEqual(Set(result.map(\.fireAt)).count, result.count)
    }
}
