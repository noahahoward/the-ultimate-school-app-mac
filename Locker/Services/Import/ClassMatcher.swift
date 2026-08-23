import Foundation

/// Works out which class an imported item belongs to.
///
/// A screenshot of an assignment often names the teacher but not the course, so
/// the teacher is frequently the only link back to a class. Matching stops short
/// of guessing: when a teacher takes more than one of your classes, that is an
/// ambiguity the student resolves, not something to pick a side on.
enum ClassMatcher {

    struct Candidate: Equatable, Sendable {
        var id: String
        var name: String
        var teacher: String
        var aliases: [String]
        /// 0 = all year, 1 = first semester, 2 = second.
        var semester: Int
        /// Courses at the source already known to be this class.
        var externalIDs: [String]

        init(id: String, name: String, teacher: String = "",
             aliases: [String] = [], semester: Int = 0, externalIDs: [String] = []) {
            self.id = id
            self.name = name
            self.teacher = teacher
            self.aliases = aliases
            self.semester = semester
            self.externalIDs = externalIDs
        }
    }

    enum Match: Equatable, Sendable {
        case matched(id: String, reason: Reason)
        /// Several classes fit, so the student picks.
        case ambiguous(ids: [String], reason: Reason)
        case none

        var id: String? {
            if case .matched(let id, _) = self { return id }
            return nil
        }
    }

    enum Reason: String, Sendable {
        case className = "matched the class name"
        case link = "is the class you filed this course under before"
        case alias = "matched a nickname"
        case subject = "is the same subject"
        case teacher = "matched the teacher"
    }

    /// - Parameter semesterInForce: which semester the school is currently in,
    ///   used only to separate classes that are otherwise identical.
    /// - Parameter courseID: the course at the source, when the page names one.
    static func match(className: String, teacher: String, in candidates: [Candidate],
                      semesterInForce: Int? = nil, courseID: String = "") -> Match {
        // A course settled once is never read again. Teachers name their pages
        // as they please and rename them mid-year; the link does not care.
        if !courseID.isEmpty {
            let linked = candidates.filter { $0.externalIDs.contains(courseID) }
            if linked.count == 1 { return .matched(id: linked[0].id, reason: .link) }
        }

        // A named course always beats an inferred one.
        if !className.trimmingCharacters(in: .whitespaces).isEmpty {
            let byName = candidates.filter { SyncMerger.namesMatch($0.name, className) }
            if let match = decide(byName, reason: .className, semesterInForce: semesterInForce) {
                return match
            }

            let byAlias = candidates.filter { candidate in
                candidate.aliases.contains { SyncMerger.namesMatch($0, className) }
            }
            if let match = decide(byAlias, reason: .alias, semesterInForce: semesterInForce) {
                return match
            }

            let wanted = subjectWords(in: className)
            let bySubject = candidates.filter { sameSubject(subjectWords(in: $0.name), wanted) }
            if let match = decide(bySubject, reason: .subject, semesterInForce: semesterInForce) {
                return match
            }
        }

        guard let wanted = surname(of: teacher) else { return .none }
        let byTeacher = candidates.filter { surname(of: $0.teacher) == wanted }
        // One teacher, two of your classes: no way to tell which, so don't.
        return decide(byTeacher, reason: .teacher, semesterInForce: semesterInForce) ?? .none
    }

    /// Settles a tier, using the running semester only to break a genuine tie.
    ///
    /// A timetable holds each course twice, once per semester, so a course name
    /// on its own always fits two classes. The half of the year the school is
    /// actually in tells them apart; without that it stays the student's call.
    private static func decide(_ hits: [Candidate], reason: Reason,
                               semesterInForce: Int?) -> Match? {
        if hits.count == 1 { return .matched(id: hits[0].id, reason: reason) }
        guard hits.count > 1 else { return nil }
        if let semester = semesterInForce {
            let running = hits.filter { $0.semester == 0 || $0.semester == semester }
            if running.count == 1 { return .matched(id: running[0].id, reason: reason) }
        }
        return .ambiguous(ids: hits.map(\.id), reason: reason)
    }

    /// Whether two courses are the same subject said at different lengths.
    ///
    /// One name has to contain the other outright. Overlapping on a word or two
    /// is how Biology ends up holding the work from Health, so a partial fit
    /// counts for nothing.
    static func sameSubject(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        let smaller = lhs.count <= rhs.count ? lhs : rhs
        let larger = lhs.count <= rhs.count ? rhs : lhs
        guard smaller.count >= 2, smaller.isSubset(of: larger) else { return false }
        // Two numbers agreeing says nothing; a subject has to be named.
        return smaller.contains { $0.contains(where: \.isLetter) }
    }

    /// The words in a course name that actually name the subject.
    ///
    /// Timetables and course pages describe the same class differently — "HONORS
    /// ENGLISH 9 I" against "2026 Summer Homework: Honors ELA 9" — so the words
    /// that only say when or what kind of page it is are dropped, and the usual
    /// shortenings are written out.
    static func subjectWords(in name: String) -> Set<String> {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var kept: Set<String> = []
        for word in words {
            if noise.contains(word) { continue }
            // A year, or a semester code like s1, says when rather than what.
            if word.count == 4, let year = Int(word), (2000...2099).contains(year) { continue }
            if word.count == 2, word.hasPrefix("s"), Int(word.dropFirst()) != nil { continue }
            // A stray letter carries nothing, but the number in "English 9" does.
            if word.count < 2, word.first?.isNumber != true { continue }
            kept.insert(longhand[word] ?? word)
        }
        return kept
    }

    private static let noise: Set<String> = [
        "summer", "homework", "class", "classes", "course", "section", "period",
        "semester", "sem", "term", "quarter", "the", "and", "of", "for", "with",
        "my", "block", "hour", "hr", "i", "ii", "iii", "iv", "v", "vi",
    ]

    /// Shortenings a course name might use at either end.
    private static let longhand: [String: String] = [
        "ela": "english", "eng": "english", "lit": "literature", "lang": "language",
        "geo": "geography", "hist": "history", "gov": "government", "econ": "economics",
        "alg": "algebra", "geom": "geometry", "calc": "calculus", "precalc": "precalculus",
        "trig": "trigonometry", "stat": "statistics", "stats": "statistics",
        "bio": "biology", "chem": "chemistry", "phys": "physics", "sci": "science",
        "span": "spanish", "fit": "fitness", "found": "foundations",
        "comp": "computer", "tech": "technology", "psych": "psychology",
    ]

    private static let titles: Set<String> = [
        "mr", "mrs", "ms", "miss", "mx", "dr", "prof", "professor",
        "sr", "sra", "srta", "mme", "mlle", "coach", "sensei", "madame",
    ]

    /// Reduces a name to the part people actually key on.
    ///
    /// A screenshot says "Serena Sturgill" while a student writes "Mrs. Sturgill",
    /// so comparing full names would miss. Comparing surnames matches both.
    static func surname(of name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Gradebooks list people surname-first ("Sturgill, Serena"), where the
        // last word is the given name and taking it would match the wrong person.
        if let comma = trimmed.firstIndex(of: ",") {
            return lastNameWord(in: String(trimmed[..<comma]))
        }
        return lastNameWord(in: trimmed)
    }

    private static func lastNameWord(in text: String) -> String? {
        let words = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" })
            .map(String.init)
            .filter { !titles.contains($0) }
        guard let last = words.last, last.count >= 3 else { return nil }
        return last
    }
}
