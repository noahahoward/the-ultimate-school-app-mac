import Foundation

/// Reads schedules printed as a run of lines per class.
///
/// Student portals commonly list a class as a small stack — name, course code,
/// teacher, room, term — with the period number heading each group. There is no
/// geometry to work with when the text comes from a page rather than a picture,
/// so this keys on the shape of the run instead: a bare number starts a period,
/// a term marker ends a class.
///
/// It is deliberately about that shape rather than about any one portal, and it
/// only reports anything when it finds several classes, so a page that merely
/// contains a stray "S1" produces nothing.
enum ScheduleTextReader {

    static func classes(from lines: [String]) -> [ClassDraft] {
        var drafts: [ClassDraft] = []
        var period: Int?
        var buffer: [String] = []

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let marker = periodMarker(line) {
                // A new period begins, so anything half-collected belonged to no
                // class — a free period, or a heading.
                buffer.removeAll()
                period = marker
                continue
            }

            if let semester = termMarker(line) {
                if let draft = draft(from: buffer, period: period, semester: semester) {
                    drafts.append(draft)
                }
                buffer.removeAll()
                continue
            }

            buffer.append(line)
            // Runaway guard: without a term marker this would swallow the page.
            if buffer.count > 8 { buffer.removeFirst() }
        }

        return merge(drafts)
    }

    static func classes(from ocr: OCRResult) -> [ClassDraft] {
        classes(from: ocr.lines.map(\.text))
    }

    // MARK: - Markers

    /// A period number alone on its line. Zero is common for a free first slot.
    static func periodMarker(_ line: String) -> Int? {
        guard line.count <= 2, line.allSatisfy(\.isNumber), let value = Int(line),
              (0...12).contains(value) else { return nil }
        return value
    }

    /// The term a class runs in, ending its group. Returns 0 for all year.
    static func termMarker(_ line: String) -> Int? {
        let text = line.trimmingCharacters(in: .whitespaces).uppercased()
        switch text {
        case "S1", "SEM 1", "SEMESTER 1", "FALL": return 1
        case "S2", "SEM 2", "SEMESTER 2", "SPRING": return 2
        case "FY", "YR", "FULL YEAR", "ALL YEAR", "YEAR": return 0
        default: return nil
        }
    }

    /// A catalogue code such as "MAT220 / 08" or "ENG-171".
    ///
    /// Its position matters more than its value: everything before it is the
    /// course name, everything after it is who teaches it and where.
    static func isCourseCode(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.count <= 20 else { return false }
        guard text.contains(where: \.isNumber) else { return false }
        // Only the slash separates the code from its section. A hyphen belongs
        // to the code itself, as in "ENG-171".
        let head = text.split(separator: "/").first.map(String.init) ?? text
        let core = head.filter { $0.isLetter || $0.isNumber }
        guard core.count >= 4, core.count <= 10 else { return false }
        let letters = core.prefix { $0.isLetter }
        let digits = core.dropFirst(letters.count)
        return letters.count >= 2 && digits.count >= 2 && digits.allSatisfy(\.isNumber)
    }

    // MARK: - One class

    static func draft(from lines: [String], period: Int?, semester: Int) -> ClassDraft? {
        guard let name = lines.first, name.count >= 3 else { return nil }
        // A group with no code is a heading or a free period, not a class.
        guard let codeIndex = lines.firstIndex(where: isCourseCode) else { return nil }

        let after = Array(lines.dropFirst(codeIndex + 1))
        var draft = ClassDraft()
        draft.name = name
        draft.semester = semester
        draft.period = period ?? CardReader.periodIn(name)
        draft.teacher = after.first { isPersonName($0) } ?? ""
        draft.room = after.last { isRoom($0) } ?? ""
        draft.sourceLine = lines.joined(separator: " · ")
        return draft
    }

    /// Whoever teaches it: words and nothing else.
    ///
    /// Course names in these listings are capitalised too, so case is no help —
    /// what separates them is that a course name carries a number, a numeral or a
    /// slash ("BIOLOGY I", "FOUND HEALTH/FIT I"), and a person's name does not.
    static func isPersonName(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.count >= 5, text.count <= 40 else { return false }
        guard !text.contains(where: \.isNumber) else { return false }
        guard !text.contains("/") else { return false }

        let words = text.split(whereSeparator: { $0 == " " || $0 == "," })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard (2...3).contains(words.count) else { return false }
        // A trailing roman numeral means a course, not a person.
        guard !["I", "II", "III", "IV"].contains(words.last?.uppercased() ?? "") else { return false }
        return words.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" || $0 == "." } }
    }

    /// A room label: short, and not prose.
    static func isRoom(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard (1...8).contains(text.count) else { return false }
        guard !text.contains(" ") else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// A week's timetable repeats the same classes for each day, so the same
    /// class arrives once per weekday.
    static func merge(_ drafts: [ClassDraft]) -> [ClassDraft] {
        var kept: [ClassDraft] = []
        for draft in drafts {
            let alreadyHave = kept.contains {
                $0.name == draft.name && $0.period == draft.period && $0.semester == draft.semester
            }
            if !alreadyHave { kept.append(draft) }
        }
        return kept.sorted {
            ($0.period ?? 99, $0.semester) < ($1.period ?? 99, $1.semester)
        }
    }
}
