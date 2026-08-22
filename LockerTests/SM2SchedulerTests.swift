import XCTest
@testable import Locker

final class SM2SchedulerTests: XCTestCase {

    let now = TestClock.date(2026, 9, 3, 18, 0)

    func testFirstGoodReviewIsOneDayOut() {
        let outcome = SM2Scheduler.apply(rating: .good, to: SM2State(), now: now)
        XCTAssertEqual(outcome.state.intervalDays, 1)
        XCTAssertEqual(outcome.state.repetitions, 1)
        XCTAssertEqual(outcome.dueAt.timeIntervalSince(now), 86_400, accuracy: 1)
    }

    func testSecondGoodReviewIsSixDaysOut() {
        let first = SM2Scheduler.apply(rating: .good, to: SM2State(), now: now)
        let second = SM2Scheduler.apply(rating: .good, to: first.state, now: now)
        XCTAssertEqual(second.state.intervalDays, 6)
        XCTAssertEqual(second.state.repetitions, 2)
    }

    func testThirdGoodReviewMultipliesByEase() {
        var state = SM2State()
        for _ in 0..<2 { state = SM2Scheduler.apply(rating: .good, to: state, now: now).state }
        let third = SM2Scheduler.apply(rating: .good, to: state, now: now)
        XCTAssertEqual(third.state.intervalDays, (6 * 2.5).rounded())
    }

    func testAgainResetsAndComesBackInMinutes() {
        var state = SM2State()
        for _ in 0..<3 { state = SM2Scheduler.apply(rating: .good, to: state, now: now).state }
        let lapse = SM2Scheduler.apply(rating: .again, to: state, now: now)

        XCTAssertEqual(lapse.state.repetitions, 0)
        XCTAssertEqual(lapse.state.lapses, 1)
        XCTAssertLessThan(lapse.state.easeFactor, state.easeFactor)
        XCTAssertEqual(lapse.dueAt.timeIntervalSince(now), SM2Scheduler.relearnMinutes * 60, accuracy: 1)
    }

    func testHardShrinksEaseAndGrowsSlowly() {
        var state = SM2State()
        for _ in 0..<3 { state = SM2Scheduler.apply(rating: .good, to: state, now: now).state }
        let hard = SM2Scheduler.apply(rating: .hard, to: state, now: now)

        XCTAssertLessThan(hard.state.easeFactor, state.easeFactor)
        XCTAssertGreaterThan(hard.state.intervalDays, state.intervalDays)
        XCTAssertLessThan(hard.state.intervalDays, state.intervalDays * state.easeFactor)
    }

    func testEasyGrowsFasterThanGood() {
        var state = SM2State()
        for _ in 0..<3 { state = SM2Scheduler.apply(rating: .good, to: state, now: now).state }
        let good = SM2Scheduler.apply(rating: .good, to: state, now: now)
        let easy = SM2Scheduler.apply(rating: .easy, to: state, now: now)
        XCTAssertGreaterThan(easy.state.intervalDays, good.state.intervalDays)
        XCTAssertGreaterThan(easy.state.easeFactor, good.state.easeFactor)
    }

    func testEaseIsClamped() {
        var state = SM2State()
        for _ in 0..<20 { state = SM2Scheduler.apply(rating: .again, to: state, now: now).state }
        XCTAssertEqual(state.easeFactor, SM2Scheduler.minimumEase, accuracy: 0.0001)

        var high = SM2State()
        for _ in 0..<20 { high = SM2Scheduler.apply(rating: .easy, to: high, now: now).state }
        XCTAssertLessThanOrEqual(high.easeFactor, SM2Scheduler.maximumEase)
    }

    func testIntervalIsCapped() {
        var state = SM2State()
        for _ in 0..<30 { state = SM2Scheduler.apply(rating: .easy, to: state, now: now).state }
        XCTAssertLessThanOrEqual(state.intervalDays, SM2Scheduler.maximumIntervalDays)
    }

    func testPreviewLabels() {
        XCTAssertEqual(SM2Scheduler.previewLabel(rating: .again, state: SM2State(), now: now), "10m")
        XCTAssertEqual(SM2Scheduler.previewLabel(rating: .good, state: SM2State(), now: now), "1d")
    }
}
