import Foundation

public struct SM2State: Equatable, Sendable {
    public var easeFactor: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int

    public init(easeFactor: Double = 2.5, intervalDays: Double = 0, repetitions: Int = 0, lapses: Int = 0) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
    }
}

public struct SM2Outcome: Equatable, Sendable {
    public var state: SM2State
    public var dueAt: Date
}

/// SM-2 spaced repetition, adapted to the four-button rating students actually see.
public enum SM2Scheduler {
    public static let minimumEase = 1.3
    public static let maximumEase = 2.7
    public static let maximumIntervalDays = 365.0
    /// "Again" puts the card back in the current session rather than tomorrow.
    public static let relearnMinutes = 10.0

    public static func apply(rating: ReviewRating, to state: SM2State, now: Date = Date()) -> SM2Outcome {
        var next = state

        switch rating {
        case .again:
            next.repetitions = 0
            next.lapses += 1
            next.easeFactor = clampEase(state.easeFactor - 0.20)
            next.intervalDays = relearnMinutes / (24 * 60)
            return SM2Outcome(state: next, dueAt: now.addingTimeInterval(relearnMinutes * 60))

        case .hard:
            next.easeFactor = clampEase(state.easeFactor - 0.15)
            next.repetitions = state.repetitions + 1
            next.intervalDays = state.repetitions == 0 ? 1 : max(1, state.intervalDays * 1.2)

        case .good:
            next.easeFactor = state.easeFactor
            next.repetitions = state.repetitions + 1
            switch state.repetitions {
            case 0: next.intervalDays = 1
            case 1: next.intervalDays = 6
            default: next.intervalDays = state.intervalDays * state.easeFactor
            }

        case .easy:
            next.easeFactor = clampEase(state.easeFactor + 0.15)
            next.repetitions = state.repetitions + 1
            switch state.repetitions {
            case 0: next.intervalDays = 3
            case 1: next.intervalDays = 8
            default: next.intervalDays = state.intervalDays * state.easeFactor * 1.3
            }
        }

        next.intervalDays = min(maximumIntervalDays, max(1, next.intervalDays.rounded()))
        let due = now.addingTimeInterval(next.intervalDays * 24 * 60 * 60)
        return SM2Outcome(state: next, dueAt: due)
    }

    static func clampEase(_ value: Double) -> Double {
        min(maximumEase, max(minimumEase, value))
    }

    /// Short human label for how far out a rating pushes a card, shown on the buttons.
    public static func previewLabel(rating: ReviewRating, state: SM2State, now: Date = Date()) -> String {
        let outcome = apply(rating: rating, to: state, now: now)
        let days = outcome.state.intervalDays
        if days < 1 { return "10m" }
        if days < 30 { return "\(Int(days))d" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return "\(Int((days / 365).rounded()))y"
    }
}
