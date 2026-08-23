import Foundation
import CoreGraphics

/// Reads pages where each class is its own visual card rather than a row.
///
/// A Google Classroom or Canvas dashboard lays classes out as tiles: the name,
/// the period and the teacher stacked inside a box, four boxes across. Flattening
/// that to text interleaves the tiles and loses which teacher belongs to which
/// class, so this works on the geometry instead — lines that sit on top of one
/// another and close together are one card.
enum CardReader {

    /// Lines this far apart vertically belong to different cards. Tuned against
    /// real dashboards: within a card lines sit about two line-heights apart,
    /// between cards several times that.
    static let maximumGap: CGFloat = 0.045

    static func classes(from ocr: OCRResult) -> [ClassDraft] {
        let usable = ocr.lines.filter { !isChrome($0.text) || periodInName($0.text) != nil }
        guard usable.count >= 4 else { return [] }

        let drafts = clusters(of: usable).compactMap(draft(from:))
        return merge(drafts)
    }

    // MARK: - Clustering

    /// Groups lines that overlap horizontally and sit close together vertically.
    static func clusters(of lines: [OCRLine]) -> [[OCRLine]] {
        var parent = Array(0..<lines.count)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current { parent[current] = parent[parent[current]]; current = parent[current] }
            return current
        }
        func join(_ a: Int, _ b: Int) {
            let x = root(a), y = root(b)
            if x != y { parent[x] = y }
        }

        for i in lines.indices {
            for j in lines.indices where j > i {
                let a = lines[i].box, b = lines[j].box
                guard min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0 else { continue }
                guard abs(a.midY - b.midY) <= maximumGap else { continue }
                join(i, j)
            }
        }

        var grouped: [Int: [OCRLine]] = [:]
        for index in lines.indices { grouped[root(index), default: []].append(lines[index]) }
        return grouped.values
            .map { $0.sorted { $0.box.midY > $1.box.midY } }
            .filter { $0.count >= 2 }
    }

    // MARK: - Reading a card

    static func draft(from card: [OCRLine]) -> ClassDraft? {
        let texts = card.map(\.text)
        // A card's title is its top line. Searching the whole card for something
        // "name-shaped" instead picks the wrong one both ways: it reads
        // "Summer Homework" as a teacher and skips the class, and it promotes an
        // assignment preview ("Due Wednesday / Summer Homework / Assignment
        // 2026") into a class of its own.
        guard let name = texts.first, isCourseName(name) else { return nil }

        let teacher = texts.dropFirst().first { isTeacherName($0) } ?? ""
        let period = texts.compactMap { periodIn($0) }.first
        // A card with nothing but a name could be any heading on the page.
        guard !teacher.isEmpty || period != nil else { return nil }

        var draft = ClassDraft()
        draft.name = name
        draft.teacher = teacher
        draft.period = period
        draft.semester = texts.compactMap { semesterInName($0) }.first ?? 0
        draft.sourceLine = texts.joined(separator: " · ")
        return draft
    }

    /// "BIOLOGY I-3-S1" carries its period and semester in the name, which is how
    /// a school's own naming often encodes the timetable.
    static func periodInName(_ text: String) -> Int? {
        guard let range = text.range(of: #"-(\d{1,2})-[Ss]\d"#, options: .regularExpression) else { return nil }
        let digits = text[range].dropFirst().prefix { $0.isNumber }
        guard let value = Int(digits), (1...12).contains(value) else { return nil }
        return value
    }

    static func semesterInName(_ text: String) -> Int? {
        guard let range = text.range(of: #"-\d{1,2}-[Ss](\d)"#, options: .regularExpression) else { return nil }
        guard let last = text[range].last, let value = Int(String(last)), (1...2).contains(value) else { return nil }
        return value
    }

    static func periodIn(_ text: String) -> Int? {
        if let fromName = periodInName(text) { return fromName }
        if let spelled = ScheduleParsing.period(in: text) { return spelled }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy(\.isNumber), let value = Int(trimmed), (1...12).contains(value) else { return nil }
        return value
    }

    // MARK: - Telling content from furniture

    private static let furniture: Set<String> = [
        "home", "calendar", "gemini", "enrolled", "to-do", "todo", "settings",
        "archived classes", "classes", "class learning tools", "add class",
        "+ add class", "upcoming", "no work due", "stream", "classwork", "people",
        "grades", "syllabus", "school", "file", "edit", "view", "history",
        "bookmarks", "profiles", "tab", "window", "help", "brave", "chrome", "safari",
    ]

    static func isChrome(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if furniture.contains(lower) { return true }
        if lower.count < 3 { return true }
        if lower.contains("://") || lower.hasPrefix("www.") { return true }
        // A browser window title, not a class.
        if lower.hasSuffix("- classroom") || lower.hasSuffix("- google classroom") { return true }
        return false
    }

    /// Whether a card's top line names a course.
    ///
    /// Only ever asked of the top line, so it does not have to tell a course name
    /// from a person's — a card does not lead with the teacher. It only has to
    /// reject the status lines and furniture that head a non-class block.
    static func isCourseName(_ text: String) -> Bool {
        guard !isChrome(text), text.count >= 5 else { return false }
        guard text.contains(where: \.isLetter) else { return false }
        // "Smith, J" is unambiguously a person however it is positioned.
        if text.contains(","), ClassMatcher.surname(of: text) != nil { return false }

        let lower = text.lowercased()
        let statuses = ["due ", "assigned", "turned in", "missing", "posted", "no work", "view all"]
        return !statuses.contains { lower.hasPrefix($0) }
    }

    /// Two or three capitalised words and nothing else. Deliberately strict:
    /// course names look similar, so anything ambiguous is left as a name.
    static func isTeacherName(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard !["due", "assigned", "turned", "posted", "missing"].contains(where: { lower.hasPrefix($0) }) else {
            return false
        }
        if ClassMatcher.surname(of: text) != nil, text.contains(",") { return true }

        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard (2...3).contains(words.count) else { return false }
        guard !text.contains(where: \.isNumber) else { return false }
        return words.allSatisfy { word in
            word.first?.isUppercase == true && word.dropFirst().allSatisfy { $0.isLetter || $0 == "." }
        }
    }

    // MARK: - Merging

    /// The same class often appears twice — once in a sidebar list and once as a
    /// card, with one copy's name truncated. Keeps the fullest version.
    static func merge(_ drafts: [ClassDraft]) -> [ClassDraft] {
        var kept: [ClassDraft] = []

        for draft in drafts.sorted(by: { $0.name.count > $1.name.count }) {
            if let index = kept.firstIndex(where: { sameClass($0, draft) }) {
                if kept[index].teacher.isEmpty { kept[index].teacher = draft.teacher }
                if kept[index].period == nil { kept[index].period = draft.period }
                if kept[index].semester == 0 { kept[index].semester = draft.semester }
            } else {
                kept.append(draft)
            }
        }
        return kept.sorted { ($0.period ?? 99) < ($1.period ?? 99) }
    }

    static func sameClass(_ lhs: ClassDraft, _ rhs: ClassDraft) -> Bool {
        if let a = lhs.period, let b = rhs.period, a != b { return false }
        return sharesOpening(lhs.name, rhs.name)
    }

    /// Truncated names ("FOUND HEALTH/FITTA" for "FOUND HEALTH/FIT I-2-S1") only
    /// agree at the start, so that is what is compared.
    static func sharesOpening(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let a = key(lhs), b = key(rhs)
        guard a.count >= 6, b.count >= 6 else { return a == b }
        let length = min(a.count, b.count, 12)
        return a.prefix(length) == b.prefix(length)
    }
}
