import Foundation

/// Turns a read page into classes.
///
/// Course links are the anchor: each one is a class, its address carries an id
/// that survives a rename, and its text is the whole name rather than the
/// clipped version on screen. The block around the link supplies the rest —
/// teacher, period — read with the same rules as a screenshot card.
enum DOMClassReader {

    /// Links that identify a course on the sites students actually use.
    static func isCourseLink(_ href: String) -> Bool {
        guard let url = URL(string: href) else { return false }
        let host = url.host ?? ""
        let path = url.path

        if host.contains("classroom.google.com") {
            // /c/<id> is a course; /c/<id>/a/<id>/details is one assignment.
            let parts = path.split(separator: "/").map(String.init)
            return parts.count == 2 && parts[0] == "c"
        }
        if host.contains("instructure.com") {
            let parts = path.split(separator: "/").map(String.init)
            return parts.count == 2 && parts[0] == "courses"
        }
        return false
    }

    static func classes(from page: PageContent) -> [ClassDraft] {
        var drafts: [ClassDraft] = []
        var seen = Set<String>()

        for link in page.links where isCourseLink(link.href) {
            guard seen.insert(link.href).inserted else { continue }
            guard let draft = draft(from: link) else { continue }
            drafts.append(draft)
        }
        return drafts.sorted { ($0.period ?? 99) < ($1.period ?? 99) }
    }

    static func draft(from link: PageContent.Link) -> ClassDraft? {
        // The link's own text is the full name; the label is a fallback for
        // sites that put the name in aria-label and an icon in the link.
        let name = pick(link.text, link.label)
        guard !name.isEmpty, name.count >= 3 else { return nil }

        var draft = ClassDraft()
        draft.name = name

        let lines = link.card
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        draft.teacher = lines.first { $0 != name && CardReader.isTeacherName($0) } ?? ""
        draft.period = ([name] + lines).compactMap { CardReader.periodIn($0) }.first
        draft.semester = ([name] + lines).compactMap { CardReader.semesterInName($0) }.first ?? 0
        draft.sourceLine = lines.isEmpty ? name : lines.joined(separator: " · ")
        return draft
    }

    /// Prefers whichever of the two says more, since sites differ over which
    /// carries the full name.
    private static func pick(_ text: String, _ label: String) -> String {
        let a = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        // A label that merely repeats the text with decoration is no better.
        return b.count > a.count && b.contains(a) ? b : a
    }

    /// When no course links are found the page still has its text, which the
    /// ordinary readers can work on.
    static func fallbackLines(from page: PageContent) -> OCRResult {
        DocumentReader.lines(fromText: page.text)
    }
}
