import Foundation
import SwiftData

@Model
final class Deck {
    var name: String = ""
    var deckDescription: String = ""
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var schoolClass: SchoolClass?

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []

    init(name: String, schoolClass: SchoolClass? = nil, deckDescription: String = "") {
        self.name = name
        self.schoolClass = schoolClass
        self.deckDescription = deckDescription
        self.createdAt = Date()
    }

    func dueCards(asOf date: Date = Date()) -> [Card] {
        cards.filter { $0.isDue(asOf: date) }
    }
}

@Model
final class Card {
    var front: String = ""
    var back: String = ""
    var createdAt: Date = Date()

    // SM-2 state
    var easeFactor: Double = 2.5
    var intervalDays: Double = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var dueAt: Date?
    var lastReviewedAt: Date?

    var deck: Deck?

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    var reviews: [ReviewLog] = []

    init(front: String, back: String, deck: Deck? = nil) {
        self.front = front
        self.back = back
        self.deck = deck
        self.createdAt = Date()
    }

    /// A never-reviewed card (nil `dueAt`) counts as due.
    func isDue(asOf date: Date = Date()) -> Bool {
        guard let dueAt else { return true }
        return dueAt <= date
    }

    var srsState: SM2State {
        get { SM2State(easeFactor: easeFactor, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses) }
        set {
            easeFactor = newValue.easeFactor
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            lapses = newValue.lapses
        }
    }
}

@Model
final class ReviewLog {
    var reviewedAt: Date = Date()
    var ratingRaw: Int = ReviewRating.good.rawValue
    var intervalAfterDays: Double = 0
    var card: Card?

    init(reviewedAt: Date = Date(), rating: ReviewRating, intervalAfterDays: Double, card: Card? = nil) {
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.intervalAfterDays = intervalAfterDays
        self.card = card
    }

    var rating: ReviewRating {
        get { ReviewRating(rawValue: ratingRaw) ?? .good }
        set { ratingRaw = newValue.rawValue }
    }
}

@Model
final class FocusSession {
    var startedAt: Date = Date()
    var endedAt: Date?
    var plannedSeconds: Int = 25 * 60
    var completedSeconds: Int = 0
    var phaseRaw: String = FocusPhase.focus.rawValue
    /// False when the timer was stopped early.
    var wasCompleted: Bool = false
    var assignment: Assignment?

    init(startedAt: Date = Date(), plannedSeconds: Int, phase: FocusPhase = .focus, assignment: Assignment? = nil) {
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.phaseRaw = phase.rawValue
        self.assignment = assignment
    }

    var phase: FocusPhase {
        get { FocusPhase(rawValue: phaseRaw) ?? .focus }
        set { phaseRaw = newValue.rawValue }
    }

    var completedMinutes: Int { completedSeconds / 60 }
}

@Model
final class GradeCategory {
    var name: String = ""
    /// Percentage of the final grade, e.g. 40 for "Tests 40%".
    var weight: Double = 0
    var sortIndex: Int = 0
    var schoolClass: SchoolClass?

    @Relationship(deleteRule: .nullify, inverse: \Assignment.gradeCategory)
    var assignments: [Assignment] = []

    init(name: String, weight: Double, schoolClass: SchoolClass? = nil, sortIndex: Int = 0) {
        self.name = name
        self.weight = weight
        self.schoolClass = schoolClass
        self.sortIndex = sortIndex
    }
}
