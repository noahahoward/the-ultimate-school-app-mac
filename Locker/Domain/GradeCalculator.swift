import Foundation

public struct GradeItem: Equatable, Sendable {
    public var score: Double
    public var maxScore: Double
    public var categoryID: String?

    public init(score: Double, maxScore: Double, categoryID: String? = nil) {
        self.score = score
        self.maxScore = maxScore
        self.categoryID = categoryID
    }
}

public struct CategoryDef: Equatable, Sendable {
    public var id: String
    public var name: String
    public var weight: Double

    public init(id: String, name: String, weight: Double) {
        self.id = id
        self.name = name
        self.weight = weight
    }
}

public struct CategoryResult: Equatable, Sendable {
    public var category: CategoryDef
    public var earned: Double
    public var possible: Double
    public var itemCount: Int

    public var percent: Double? {
        possible > 0 ? earned / possible * 100 : nil
    }
}

public enum GradeCalculator {

    /// Current grade as a percentage, or nil when nothing has been graded yet.
    ///
    /// Categories with no graded work are left out and the remaining weights are
    /// renormalized — otherwise a class would look like a 40% in September just
    /// because the final exam hasn't happened.
    public static func percent(
        items: [GradeItem],
        categories: [CategoryDef],
        mode: GradingMode
    ) -> Double? {
        let graded = items.filter { $0.maxScore > 0 }
        guard !graded.isEmpty else { return nil }

        switch mode {
        case .totalPoints:
            let earned = graded.reduce(0) { $0 + $1.score }
            let possible = graded.reduce(0) { $0 + $1.maxScore }
            guard possible > 0 else { return nil }
            return earned / possible * 100

        case .weightedCategories:
            let results = breakdown(items: graded, categories: categories)
            let active = results.filter { $0.possible > 0 && $0.category.weight > 0 }
            guard !active.isEmpty else {
                // No usable categories: fall back to straight points so the
                // student still sees a number instead of a blank.
                return percent(items: graded, categories: [], mode: .totalPoints)
            }
            let totalWeight = active.reduce(0) { $0 + $1.category.weight }
            guard totalWeight > 0 else { return nil }
            let weighted = active.reduce(0.0) { sum, result in
                sum + (result.percent ?? 0) * result.category.weight
            }
            return weighted / totalWeight
        }
    }

    public static func breakdown(items: [GradeItem], categories: [CategoryDef]) -> [CategoryResult] {
        categories.map { category in
            let matching = items.filter { $0.categoryID == category.id && $0.maxScore > 0 }
            return CategoryResult(
                category: category,
                earned: matching.reduce(0) { $0 + $1.score },
                possible: matching.reduce(0) { $0 + $1.maxScore },
                itemCount: matching.count
            )
        }
    }

    /// Percentage needed on an upcoming weighted assessment to finish at `target`.
    /// Returns nil when the weight is zero. May return values above 100 (impossible)
    /// or below 0 (already locked in) — the UI says so plainly rather than hiding it.
    public static func scoreNeeded(
        toReach target: Double,
        currentPercent: Double,
        assessmentWeight: Double
    ) -> Double? {
        guard assessmentWeight > 0, assessmentWeight <= 100 else { return nil }
        let carried = currentPercent * (100 - assessmentWeight) / 100
        return (target - carried) * 100 / assessmentWeight
    }

    /// Same question in a points-based class.
    public static func scoreNeeded(
        toReach target: Double,
        earnedPoints: Double,
        possiblePoints: Double,
        upcomingPoints: Double
    ) -> Double? {
        guard upcomingPoints > 0 else { return nil }
        let needed = target / 100 * (possiblePoints + upcomingPoints) - earnedPoints
        return needed / upcomingPoints * 100
    }

    // MARK: - Letters

    public static let letterCutoffs: [(letter: String, minimum: Double)] = [
        ("A+", 97), ("A", 93), ("A-", 90),
        ("B+", 87), ("B", 83), ("B-", 80),
        ("C+", 77), ("C", 73), ("C-", 70),
        ("D+", 67), ("D", 63), ("D-", 60),
        ("F", 0),
    ]

    public static func letter(for percent: Double) -> String {
        letterCutoffs.first { percent >= $0.minimum }?.letter ?? "F"
    }

    /// Standard 4.0 scale, unweighted.
    public static func gradePoints(for percent: Double) -> Double {
        switch percent {
        case 93...: 4.0
        case 90..<93: 3.7
        case 87..<90: 3.3
        case 83..<87: 3.0
        case 80..<83: 2.7
        case 77..<80: 2.3
        case 73..<77: 2.0
        case 70..<73: 1.7
        case 67..<70: 1.3
        case 63..<67: 1.0
        case 60..<63: 0.7
        default: 0.0
        }
    }

    public static func gpa(percents: [Double]) -> Double? {
        guard !percents.isEmpty else { return nil }
        return percents.map(gradePoints(for:)).reduce(0, +) / Double(percents.count)
    }
}
