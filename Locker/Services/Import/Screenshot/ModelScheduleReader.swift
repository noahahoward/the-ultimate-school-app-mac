import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a schedule the pattern reader didn't recognise.
///
/// Every school prints its timetable differently — periods, bare times, day
/// letters, a grid — so a pattern that fits one district will miss the next. The
/// model's job is only to find the rows and say which text is which column; it
/// never converts a time, works out a day, or names a class that isn't printed.
enum ModelScheduleReader {

    static var isAvailable: Bool { ScreenshotExtractor.isModelAvailable }

    /// Nil when the model is unavailable, declines, or says this isn't a schedule.
    static func read(ocrText: String) async -> [ClassDraft]? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await Reader.read(ocrText: ocrText)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable(description: "One class as printed on a school schedule.")
struct ScheduleRowSlots {

    @Guide(description: "The course name, copied exactly as printed. Never a room, a teacher, or a time.")
    var name: String

    @Guide(description: "The period as printed, such as 'Period 3' or '3'. Empty if the schedule shows no period.")
    var periodText: String

    @Guide(description: "The term as printed, such as 'SEMESTER 1', 'Fall', or 'Full Year'. Empty if none is shown.")
    var termText: String

    @Guide(description: "The teacher's name as printed. Empty if none is shown.")
    var teacher: String

    @Guide(description: "The room as printed, such as '204' or 'Rm 118'. Empty if none is shown.")
    var roomText: String

    @Guide(description: "The class times as printed, such as '9:02-9:54'. Do not convert them. Empty if none are shown.")
    var timeText: String

    @Guide(description: "The days it meets as printed, such as 'M W F'. Empty if none are shown.")
    var daysText: String
}

@available(macOS 26.0, *)
@Generable(description: "Classes read from a screenshot of a school schedule.")
struct ScheduleSlots {

    @Guide(description: "True only when the text lists several school classes forming a timetable. False for a single assignment, a grade report, or anything else.")
    var isSchedule: Bool

    @Guide(description: "One entry for each class listed, in the order they appear. Empty when this is not a schedule.")
    var classes: [ScheduleRowSlots]
}

@available(macOS 26.0, *)
private enum Reader {

    static let instructions = """
        You are reading text captured from a screenshot of a school schedule.

        Rules:
        - Copy text exactly as it appears. Never reword, correct, or reformat it.
        - Never work anything out. Do not convert a time, a day, or a period number.
        - List one entry per class. Do not merge two classes or split one in half.
        - If a column is not printed for a class, leave that field empty.
        - An empty field is always better than a guess.
        - If the text is not a timetable, say so and return no classes.
        """

    static func read(ocrText: String) async -> [ClassDraft]? {
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
            Here is every line of text read from the screenshot, in order:

            \(ocrText)

            List the classes using only that text.
            """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: ScheduleSlots.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let slots = response.content
            guard slots.isSchedule, !slots.classes.isEmpty else { return nil }

            let haystack = EvidenceCheck.normalize(ocrText)
            let rows = slots.classes.compactMap { row -> ClassDraft? in
                draft(from: row, haystack: haystack)
            }
            // A single row is more likely a misread of an assignment page than a
            // timetable, and the assignment path handles that far better.
            return rows.count >= 2 ? rows : nil
        } catch {
            return nil
        }
    }

    /// Builds a row, dropping any field the screenshot doesn't actually contain.
    static func draft(from row: ScheduleRowSlots, haystack: String) -> ClassDraft? {
        func verified(_ value: String) -> String {
            let trimmed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !trimmed.isEmpty, EvidenceCheck.isSupported(trimmed, by: haystack) else { return "" }
            return trimmed
        }

        // A class with a name that isn't on screen is invented, so it is dropped
        // outright rather than offered for review.
        let name = verified(row.name)
        guard !name.isEmpty else { return nil }

        var draft = ClassDraft()
        draft.name = name
        draft.teacher = verified(row.teacher)
        draft.room = verified(row.roomText)

        let periodText = verified(row.periodText)
        draft.period = ScheduleFieldParsing.period(from: periodText)

        let termText = verified(row.termText)
        draft.semester = ScheduleFieldParsing.semester(from: termText)

        let timeText = verified(row.timeText)
        if let times = ScheduleFieldParsing.times(from: timeText) {
            draft.startMinutes = times.start
            draft.endMinutes = times.end
        }

        draft.weekdays = ScheduleFieldParsing.weekdays(from: verified(row.daysText))

        draft.sourceLine = [name, periodText, termText, draft.teacher, draft.room, timeText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return draft
    }
}

#endif
