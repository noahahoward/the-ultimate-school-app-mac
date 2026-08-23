import Foundation

/// Turns a read page into classes.
///
/// Course links are the anchor: each one is a class, its address carries an id
/// that survives a rename, and its text is the whole name rather than the
/// clipped version on screen. The block around the link supplies the rest —
/// teacher, period — read with the same rules as a screenshot card.
enum DOMClassReader {

    /// The course this link addresses, if it addresses one.
    ///
    /// Real links carry an account prefix — "/u/2/c/<id>" — and the same course
    /// is linked several times over: the sidebar entry, the card, the tile's
    /// "open your work". They all share the id, which is what ties them together.
    static func courseID(in href: String) -> String? {
        guard let url = URL(string: href) else { return nil }
        let host = url.host ?? ""
        let parts = url.path.split(separator: "/").map(String.init)

        if host.contains("classroom.google.com") {
            // ".../c/<id>" and nothing after it: deeper paths are assignments.
            guard let index = parts.lastIndex(of: "c"), index == parts.count - 2 else { return nil }
            return parts[index + 1]
        }
        if host.contains("instructure.com") {
            guard let index = parts.lastIndex(of: "courses"), index == parts.count - 2 else { return nil }
            return parts[index + 1]
        }
        return nil
    }

    static func isCourseLink(_ href: String) -> Bool { courseID(in: href) != nil }

    static func classes(from page: PageContent) -> [ClassDraft] {
        var byCourse: [String: [PageContent.Link]] = [:]
        for link in page.links {
            guard let id = courseID(in: link.href) else { continue }
            byCourse[id, default: []].append(link)
        }

        let drafts = byCourse.compactMap { _, links -> ClassDraft? in draft(forCourse: links) }
        return drafts.sorted { ($0.period ?? 99) < ($1.period ?? 99) }
    }

    /// Builds one class from every link that points at it.
    static func draft(forCourse links: [PageContent.Link]) -> ClassDraft? {
        guard let name = name(from: links), name.count >= 3 else { return nil }
        let cardLines = lines(of: card(for: name, among: links))

        var draft = ClassDraft()
        draft.name = name
        draft.teacher = cardLines.first { $0 != name && !isFurniture($0) && CardReader.isTeacherName($0) } ?? ""
        draft.period = ([name] + cardLines).compactMap { CardReader.periodIn($0) }.first
        draft.semester = ([name] + cardLines).compactMap { CardReader.semesterInName($0) }.first ?? 0
        draft.sourceLine = cardLines.prefix(4).joined(separator: " · ")
        return draft
    }

    /// The class's own name, from a link whose text is laid out over lines.
    ///
    /// A tile leads with a one-letter avatar, so the name is the first line with
    /// anything to it. The run-together variant of the same link — where every
    /// line has been concatenated — is skipped, since its name would carry the
    /// avatar letter and the section fused on.
    static func name(from links: [PageContent.Link]) -> String? {
        // Laid-out text first: it separates the avatar from the name.
        for link in links where link.text.contains("\n") {
            if let found = firstMeaningful(lines(of: link.text)) { return found }
        }
        // Then a label, which sites often set to the plain name.
        if let label = links.lazy
            .map({ $0.label.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) {
            return label
        }
        // Finally single-line text, for sites that put the name in the link and
        // nothing else around it.
        return links.lazy.compactMap { firstMeaningful(lines(of: $0.text)) }.first
    }

    /// The tile belonging to this class, rather than the list it sits in.
    ///
    /// A class's own tile begins with its name — but so does the sidebar for
    /// whichever class comes first, and that blob holds every class at once. The
    /// tightest block that begins with the name is the one that belongs to it.
    static func card(for name: String, among links: [PageContent.Link]) -> String {
        let owned = links.filter {
            let cardLines = lines(of: $0.card)
            return cardLines.count >= 2 && firstMeaningful(cardLines) == name
        }
        if let tightest = owned.min(by: { lines(of: $0.card).count < lines(of: $1.card).count }) {
            return tightest.card
        }
        return links.max { lines(of: $0.card).count < lines(of: $1.card).count }?.card ?? ""
    }

    private static func firstMeaningful(_ lines: [String]) -> String? {
        lines.first { $0.count >= 3 && !isFurniture($0) }
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Controls and helper links that sit inside a class tile.
    static func isFurniture(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("open your work") || lower.hasPrefix("open folder") { return true }
        if lower.hasPrefix("more options") || lower == "more_vert" { return true }
        if ["to-do", "enrolled", "class", "assignment", "learn with gemini"].contains(lower) { return true }
        return false
    }

    /// When no course links are found the page still has its text, which the
    /// ordinary readers can work on.
    static func fallbackLines(from page: PageContent) -> OCRResult {
        DocumentReader.lines(fromText: page.text)
    }
}
