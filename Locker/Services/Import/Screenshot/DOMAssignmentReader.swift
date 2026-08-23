import Foundation

/// Work read from a page, ready for review.
struct AssignmentDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = ""
    var className = ""
    var dueAt: Date?
    var hasDueTime = false
    var type: AssignmentType = .homework
    /// The address it came from, which identifies it across readings.
    var externalID = ""
    var url = ""
    var sourceLine = ""
    var include = true
}

/// Pulls assignments out of a page.
///
/// Classroom's to-do view is the page worth reading: it lists everything
/// outstanding across every class, and each item is a link whose address names
/// the assignment. That address is a stable id, so the same item read twice is
/// recognised as one — which is what makes re-reading safe.
enum DOMAssignmentReader {

    /// "/c/<course>/a/<assignment>/details" — the address of one piece of work.
    static func assignmentID(in href: String) -> (course: String, assignment: String)? {
        guard let url = URL(string: href), (url.host ?? "").contains("classroom.google.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let courseIndex = parts.firstIndex(of: "c"), courseIndex + 3 < parts.count else { return nil }
        guard parts[courseIndex + 2] == "a" else { return nil }
        return (parts[courseIndex + 1], parts[courseIndex + 3])
    }

    static func assignments(
        from page: PageContent,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AssignmentDraft] {
        var byID: [String: AssignmentDraft] = [:]

        for link in page.links {
            guard let ids = assignmentID(in: link.href) else { continue }
            guard var draft = draft(from: link, now: now, calendar: calendar) else { continue }
            draft.externalID = ids.assignment
            draft.url = link.href

            // The same item is linked more than once; keep whichever reading
            // filled in the most.
            if let existing = byID[ids.assignment], score(existing) >= score(draft) { continue }
            byID[ids.assignment] = draft
        }

        return byID.values.sorted {
            ($0.dueAt ?? .distantFuture, $0.title) < ($1.dueAt ?? .distantFuture, $1.title)
        }
    }

    private static func score(_ draft: AssignmentDraft) -> Int {
        (draft.dueAt == nil ? 0 : 2) + (draft.className.isEmpty ? 0 : 1)
    }

    static func draft(from link: PageContent.Link, now: Date, calendar: Calendar = .current) -> AssignmentDraft? {
        let lines = link.card
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let title = lines.first { !isFurniture($0) }
            ?? link.text.trimmingCharacters(in: .whitespaces)
        guard title.count >= 3, !isFurniture(title) else { return nil }

        var draft = AssignmentDraft()
        draft.title = title
        draft.className = className(in: lines, excluding: title)

        if let due = lines.compactMap({ FieldParsing.dateAndTime(from: $0, now: now, calendar: calendar) }).first {
            draft.dueAt = due.date
            draft.hasDueTime = due.hasTime
        }

        draft.type = FieldParsing.type(fromTitle: title)
        draft.sourceLine = lines.prefix(4).joined(separator: " · ")
        return draft
    }

    /// The class is the line after the word "Class", which is how Classroom
    /// labels it. Failing that, a line that repeats itself in the block.
    static func className(in lines: [String], excluding title: String) -> String {
        if let marker = lines.firstIndex(where: { $0.caseInsensitiveCompare("Class") == .orderedSame }),
           marker + 1 < lines.count {
            return lines[marker + 1]
        }
        let counts = Dictionary(grouping: lines, by: { $0 }).mapValues(\.count)
        return counts.first { $0.value > 1 && $0.key != title && !isFurniture($0.key) }?.key ?? ""
    }

    /// Labels and controls that sit inside an item without describing it.
    static func isFurniture(_ line: String) -> Bool {
        let lower = line.lowercased()
        let exact: Set<String> = [
            "assignment", "material", "quiz assignment", "question", "class",
            "learn with gemini", "view details", "more options", "more_vert",
            "assigned", "turned in", "done", "missing", "no due date",
        ]
        if exact.contains(lower) { return true }
        if lower.hasPrefix("open ") || lower.hasPrefix("view ") { return true }
        return line.count < 3
    }
}

/// Whether a page is asking for a sign-in rather than showing anything.
enum SignInDetector {

    /// Recognised from the address first, since a redirect to an accounts page
    /// is unambiguous, and only then from what the page says.
    static func isSignInPage(_ page: PageContent) -> Bool {
        let url = page.url.lowercased()
        if url.contains("accounts.google.com") || url.contains("/signin") || url.contains("/login") {
            return true
        }

        let text = page.text.lowercased()
        let title = page.title.lowercased()
        let phrases = ["sign in to continue", "choose an account", "use your google account",
                       "session has expired", "please sign in", "log in to continue"]
        if phrases.contains(where: { text.contains($0) || title.contains($0) }) { return true }

        // A near-empty page titled "Sign in" is a sign-in page; a long page that
        // merely mentions signing out is not.
        return title.contains("sign in") && page.text.count < 2000
    }
}
