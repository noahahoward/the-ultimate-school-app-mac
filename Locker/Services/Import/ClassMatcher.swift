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

        init(id: String, name: String, teacher: String = "", aliases: [String] = []) {
            self.id = id
            self.name = name
            self.teacher = teacher
            self.aliases = aliases
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
        case alias = "matched a nickname"
        case teacher = "matched the teacher"
    }

    static func match(className: String, teacher: String, in candidates: [Candidate]) -> Match {
        // A named course always beats an inferred one.
        if !className.trimmingCharacters(in: .whitespaces).isEmpty {
            let byName = candidates.filter { SyncMerger.namesMatch($0.name, className) }
            if byName.count == 1 { return .matched(id: byName[0].id, reason: .className) }
            if byName.count > 1 { return .ambiguous(ids: byName.map(\.id), reason: .className) }

            let byAlias = candidates.filter { candidate in
                candidate.aliases.contains { SyncMerger.namesMatch($0, className) }
            }
            if byAlias.count == 1 { return .matched(id: byAlias[0].id, reason: .alias) }
            if byAlias.count > 1 { return .ambiguous(ids: byAlias.map(\.id), reason: .alias) }
        }

        guard let wanted = surname(of: teacher) else { return .none }
        let byTeacher = candidates.filter { surname(of: $0.teacher) == wanted }
        if byTeacher.count == 1 { return .matched(id: byTeacher[0].id, reason: .teacher) }
        // One teacher, two of your classes: no way to tell which, so don't.
        if byTeacher.count > 1 { return .ambiguous(ids: byTeacher.map(\.id), reason: .teacher) }
        return .none
    }

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
