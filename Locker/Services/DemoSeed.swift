import Foundation
import SwiftData

/// Fills an empty store with a believable week of school.
///
/// Only runs when `LOCKER_SEED=1` is set, so it never touches real data. Handy
/// for checking layout without spending ten minutes typing classes in.
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["LOCKER_SEED"] == "1"
    }

    static func populateIfEmpty(context: ModelContext, settings: AppSettings) {
        guard isRequested else { return }
        let existing = (try? context.fetch(FetchDescriptor<SchoolClass>())) ?? []
        guard existing.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        settings.hasCompletedOnboarding = true
        settings.scheduleKind = .alternatingAB
        settings.abAnchorDate = today
        settings.abAnchorIsA = true
        settings.firstDayOfSchool = calendar.date(byAdding: .day, value: -14, to: today)

        let everyDay = Weekdays.mask(from: Weekdays.schoolWeek)

        func makeClass(
            _ name: String, _ alias: String, _ teacher: String, _ room: String,
            period: Int, start: Int, minutes: Int, colorIndex: Int, ab: ABDesignation = .both
        ) -> SchoolClass {
            let schoolClass = SchoolClass(
                name: name, aliases: [alias], teacher: teacher, room: room, period: period,
                colorHex: ClassPalette.hex(forIndex: colorIndex), daysMask: everyDay,
                startMinutes: start, endMinutes: start + minutes,
                abDesignation: ab, sortIndex: period
            )
            context.insert(schoolClass)
            return schoolClass
        }

        let bio = makeClass("Biology", "bio", "Ms. Reyes", "204", period: 1, start: 8 * 60 + 5, minutes: 52, colorIndex: 3)
        let algebra = makeClass("Algebra 2", "alg", "Mr. Okafor", "118", period: 2, start: 9 * 60 + 2, minutes: 52, colorIndex: 4)
        let english = makeClass("English", "eng", "Mrs. Hale", "232", period: 3, start: 10 * 60 + 5, minutes: 52, colorIndex: 5)
        let history = makeClass("World History", "wh", "Mr. Dunn", "150", period: 4, start: 11 * 60 + 45, minutes: 52, colorIndex: 1)
        let spanish = makeClass("Spanish II", "span", "Sra. Lopez", "221", period: 5, start: 12 * 60 + 45, minutes: 52, colorIndex: 2, ab: .a)
        let art = makeClass("Studio Art", "art", "Ms. Frank", "Annex", period: 5, start: 12 * 60 + 45, minutes: 52, colorIndex: 6, ab: .b)
        _ = art
        let pe = makeClass("PE", "pe", "Coach Bell", "Gym", period: 6, start: 13 * 60 + 47, minutes: 52, colorIndex: 9)
        _ = pe

        func add(
            _ title: String, _ schoolClass: SchoolClass, dayOffset: Int?, type: AssignmentType,
            priority: Priority = .normal, minutes: Int? = nil, score: Double? = nil, maxScore: Double? = nil,
            done: Bool = false
        ) {
            var due: Date?
            if let dayOffset { due = calendar.date(byAdding: .day, value: dayOffset, to: today) }
            if let base = due, let start = schoolClass.startMinutes {
                due = ScheduleEngine.date(base, atMinutes: start)
            }
            let assignment = Assignment(
                title: title, schoolClass: schoolClass, dueAt: due,
                hasDueTime: due != nil, type: type, priority: priority, estimatedMinutes: minutes
            )
            assignment.score = score
            assignment.maxScore = maxScore
            if done { assignment.setDone(true, now: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
            context.insert(assignment)
        }

        add("Cell membrane diagram", bio, dayOffset: -1, type: .homework, minutes: 30)
        add("Unit 2 problem set", algebra, dayOffset: 0, type: .homework, priority: .high, minutes: 45)
        add("Read chapters 4–5", english, dayOffset: 0, type: .reading, minutes: 40)
        add("Vocab quiz", spanish, dayOffset: 1, type: .quiz, minutes: 20)
        add("Osmosis lab write-up", bio, dayOffset: 2, type: .lab, minutes: 60)
        add("Unit 2 test", algebra, dayOffset: 4, type: .test, priority: .high, minutes: 90)
        add("Revolutions essay draft", history, dayOffset: 6, type: .essay, minutes: 120)
        add("Study guide", history, dayOffset: nil, type: .homework)

        add("Quiz 1", algebra, dayOffset: -8, type: .quiz, score: 27, maxScore: 30, done: true)
        add("Homework set 1", algebra, dayOffset: -6, type: .homework, score: 20, maxScore: 20, done: true)
        add("Chapter 1 test", bio, dayOffset: -7, type: .test, score: 84, maxScore: 100, done: true)
        add("Lab safety quiz", bio, dayOffset: -9, type: .quiz, score: 19, maxScore: 20, done: true)
        add("Reading response", english, dayOffset: -3, type: .essay, score: 45, maxScore: 50, done: true)

        for (name, weight) in [("Tests", 50.0), ("Quizzes", 20.0), ("Homework", 30.0)] {
            context.insert(GradeCategory(name: name, weight: weight, schoolClass: algebra))
            context.insert(GradeCategory(name: name, weight: weight, schoolClass: bio))
        }

        let deck = Deck(name: "Bio Unit 2 vocab", schoolClass: bio)
        context.insert(deck)
        for (front, back) in [
            ("Osmosis", "Water moving across a membrane toward higher solute"),
            ("Diffusion", "Particles spreading from high to low concentration"),
            ("Hypertonic", "Higher solute concentration outside the cell"),
            ("Isotonic", "Equal solute concentration inside and out"),
        ] {
            context.insert(Card(front: front, back: back, deck: deck))
        }

        let spanishDeck = Deck(name: "Spanish: preterite verbs", schoolClass: spanish)
        context.insert(spanishDeck)
        for (front, back) in [("hablar", "to speak"), ("comer", "to eat"), ("vivir", "to live")] {
            context.insert(Card(front: front, back: back, deck: spanishDeck))
        }

        for dayOffset in [-3, -2, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let session = FocusSession(
                startedAt: ScheduleEngine.date(day, atMinutes: 16 * 60), plannedSeconds: 25 * 60
            )
            session.completedSeconds = 25 * 60
            session.wasCompleted = true
            session.endedAt = session.startedAt.addingTimeInterval(25 * 60)
            context.insert(session)
        }

        try? context.save()
    }
}
