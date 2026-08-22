import Foundation

/// Spots work or classes that are already in Locker.
///
/// Screenshot importing makes duplicates easy to create: the same assignment
/// page gets captured twice, or a class arrives from both Google Classroom and a
/// schedule. Rather than refuse or silently skip, this reports what it found and
/// how sure it is, and the student decides.
enum DuplicateDetector {

    struct AssignmentCandidate: Equatable, Sendable {
        var id: String
        var title: String
        var classID: String?
        var dueAt: Date?
        var isDone: Bool

        init(id: String, title: String, classID: String? = nil, dueAt: Date? = nil, isDone: Bool = false) {
            self.id = id
            self.title = title
            self.classID = classID
            self.dueAt = dueAt
            self.isDone = isDone
        }
    }

    struct ClassCandidate: Equatable, Sendable {
        var id: String
        var name: String
        var semester: Int
        var period: Int?

        init(id: String, name: String, semester: Int = 0, period: Int? = nil) {
            self.id = id
            self.name = name
            self.semester = semester
            self.period = period
        }
    }

    enum Confidence: Equatable, Sendable {
        /// Same thing beyond reasonable doubt: importing again would plainly duplicate it.
        case certain
        /// Close enough to be worth showing, but it could be a genuinely separate item.
        case possible
    }

    struct Match: Equatable, Sendable {
        var id: String
        var confidence: Confidence
        var reason: String
    }

    // MARK: - Assignments

    static func assignment(
        title: String,
        classID: String?,
        dueAt: Date?,
        among existing: [AssignmentCandidate],
        calendar: Calendar = .current
    ) -> Match? {
        let key = normalize(title)
        guard !key.isEmpty else { return nil }

        var best: Match?
        for candidate in existing {
            let candidateKey = normalize(candidate.title)
            guard !candidateKey.isEmpty else { continue }

            let sameClass = classID != nil && candidate.classID == classID
            let sameDay = sameDate(dueAt, candidate.dueAt, calendar: calendar)

            if candidateKey == key {
                // An identical title in the same class, or on the same day, is
                // the same piece of work.
                if sameClass || sameDay {
                    return Match(id: candidate.id, confidence: .certain,
                                 reason: "Same title, already in \(sameClass ? "this class" : "your list for that day")")
                }
                best = best ?? Match(id: candidate.id, confidence: .possible,
                                     reason: "You already have work with this title")
                continue
            }

            // Wording drifts between a screenshot and what was typed, so near
            // matches count when they land in the same place.
            let overlap = tokenOverlap(key, candidateKey)
            if overlap >= 0.8, sameClass || sameDay {
                best = best ?? Match(id: candidate.id, confidence: .possible,
                                     reason: "Looks like “\(candidate.title)”")
            }
        }
        return best
    }

    // MARK: - Classes

    static func schoolClass(
        name: String,
        semester: Int,
        period: Int?,
        among existing: [ClassCandidate]
    ) -> Match? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }

        for candidate in existing {
            let candidateKey = normalize(candidate.name)
            guard !candidateKey.isEmpty else { continue }

            // A class only clashes within the same semester: the same course
            // name in semester 1 and semester 2 is two different classes.
            guard candidate.semester == semester else { continue }

            if candidateKey == key {
                return Match(id: candidate.id, confidence: .certain, reason: "Already in your classes")
            }
            if SyncMerger.namesMatch(candidate.name, name) {
                let samePeriod = period != nil && candidate.period == period
                return Match(
                    id: candidate.id,
                    confidence: samePeriod ? .certain : .possible,
                    reason: samePeriod ? "Already in your classes" : "Looks like “\(candidate.name)”"
                )
            }
        }
        return nil
    }

    // MARK: - Comparison

    static func normalize(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    /// How much two titles share, as a fraction of the smaller one.
    static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").map(String.init))
        let right = Set(rhs.split(separator: " ").map(String.init))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(min(left.count, right.count))
    }

    static func sameDate(_ lhs: Date?, _ rhs: Date?, calendar: Calendar) -> Bool {
        guard let lhs, let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
