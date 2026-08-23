import XCTest
@testable import Locker

/// Reading work off Classroom's to-do view. The block around each assignment
/// link is transcribed from a real page's shape, with invented content.
final class DOMAssignmentReaderTests: XCTestCase {

    let calendar = TestClock.calendar
    lazy var now = TestClock.date(2026, 8, 23, 12, 0)

    func link(_ href: String, card: String, text: String = "", label: String = "") -> PageContent.Link {
        PageContent.Link(href: href, text: text, label: label, card: card)
    }

    var todoPage: PageContent {
        PageContent(
            url: "https://classroom.google.com/u/2/a/not-turned-in/all",
            title: "To-do - Classroom",
            links: [
                link("https://classroom.google.com/u/2/c/AAA/a/111/details",
                     card: """
                     assignment
                     Chapter 4 reading questions
                     Class
                     LIFE SCIENCE I
                     Learn with Gemini
                     Wed, Aug 26, 11:59 PM
                     """),
                link("https://classroom.google.com/u/2/c/BBB/a/222/details",
                     card: """
                     assignment
                     Unit 1 Test
                     Class
                     HUMAN GEOGRAPHY I
                     Fri, Aug 28, 8:00 AM
                     """),
                link("https://classroom.google.com/u/2/c/CCC/a/333/details",
                     card: """
                     material
                     Course syllabus
                     Class
                     WORLD LANGUAGE I
                     """),
                // A course link, not an assignment.
                link("https://classroom.google.com/u/2/c/AAA", card: "LIFE SCIENCE I"),
                link("https://classroom.google.com/u/2/settings", card: "Settings"),
            ],
            text: "To-do"
        )
    }

    var found: [AssignmentDraft] { DOMAssignmentReader.assignments(from: todoPage, now: now, calendar: calendar) }

    func testOnlyAssignmentsAreRead() {
        XCTAssertEqual(found.count, 3, "got: \(found.map(\.title))")
        XCTAssertFalse(found.contains { $0.title == "Settings" })
        XCTAssertFalse(found.contains { $0.title == "LIFE SCIENCE I" })
    }

    func testTitlesSkipTheTypeLabel() {
        // Each block leads with "assignment" or "material", which names nothing.
        XCTAssertTrue(found.contains { $0.title == "Chapter 4 reading questions" })
        XCTAssertFalse(found.contains { $0.title.lowercased() == "assignment" })
    }

    func testEachAssignmentKeepsItsOwnClass() {
        let classes = Dictionary(uniqueKeysWithValues: found.map { ($0.title, $0.className) })
        XCTAssertEqual(classes["Chapter 4 reading questions"], "LIFE SCIENCE I")
        XCTAssertEqual(classes["Unit 1 Test"], "HUMAN GEOGRAPHY I")
    }

    func testDueDatesAndTimesAreRead() {
        let reading = found.first { $0.title == "Chapter 4 reading questions" }
        XCTAssertEqual(reading?.dueAt, TestClock.date(2026, 8, 26, 23, 59))
        XCTAssertEqual(reading?.hasDueTime, true)

        let test = found.first { $0.title == "Unit 1 Test" }
        XCTAssertEqual(test?.dueAt, TestClock.date(2026, 8, 28, 8, 0))
    }

    func testSomethingWithNoDueDateIsStillRead() {
        let syllabus = found.first { $0.title == "Course syllabus" }
        XCTAssertNotNil(syllabus)
        XCTAssertNil(syllabus?.dueAt)
    }

    func testTypeIsInferredFromTheTitle() {
        XCTAssertEqual(found.first { $0.title == "Unit 1 Test" }?.type, .test)
        XCTAssertEqual(found.first { $0.title == "Chapter 4 reading questions" }?.type, .reading)
    }

    func testTheSameItemLinkedTwiceIsOneAssignment() {
        var page = todoPage
        // A second link to the same work, with less around it.
        page.links.append(link("https://classroom.google.com/u/2/c/AAA/a/111/details",
                               card: "assignment\nChapter 4 reading questions"))
        let read = DOMAssignmentReader.assignments(from: page, now: now, calendar: calendar)
        XCTAssertEqual(read.count, 3)
        // The fuller reading wins, so the due date is not lost.
        XCTAssertNotNil(read.first { $0.title == "Chapter 4 reading questions" }?.dueAt)
    }

    func testAssignmentAddressesAreToldFromCourseAddresses() {
        XCTAssertNotNil(DOMAssignmentReader.assignmentID(in: "https://classroom.google.com/u/2/c/AAA/a/111/details"))
        XCTAssertNil(DOMAssignmentReader.assignmentID(in: "https://classroom.google.com/u/2/c/AAA"))
        XCTAssertNil(DOMAssignmentReader.assignmentID(in: "https://example.com/c/AAA/a/111/details"))
    }

    // MARK: - Dates as portals write them

    func testDateAndTimeParsing() {
        XCTAssertEqual(FieldParsing.dateAndTime(from: "Wed, Aug 26, 11:59 PM", now: now, calendar: calendar)?.date,
                       TestClock.date(2026, 8, 26, 23, 59))
        XCTAssertEqual(FieldParsing.dateAndTime(from: "Aug 26", now: now, calendar: calendar)?.hasTime, false)
        XCTAssertEqual(FieldParsing.dateAndTime(from: "Due Aug 26, 3:00 PM", now: now, calendar: calendar)?.date,
                       TestClock.date(2026, 8, 26, 15, 0))
        XCTAssertNil(FieldParsing.dateAndTime(from: "Learn with Gemini", now: now, calendar: calendar))
    }

    // MARK: - Signing in

    func testASignInPageIsRecognised() {
        let redirected = PageContent(url: "https://accounts.google.com/signin/v2/identifier",
                                     title: "Sign in - Google Accounts", links: [], text: "Use your Google Account")
        XCTAssertTrue(SignInDetector.isSignInPage(redirected))

        let expired = PageContent(url: "https://classroom.google.com/u/2/h", title: "Classroom",
                                  links: [], text: "Your session has expired. Please sign in again.")
        XCTAssertTrue(SignInDetector.isSignInPage(expired))
    }

    func testARealPageIsNotMistakenForASignIn() {
        XCTAssertFalse(SignInDetector.isSignInPage(todoPage))
        // A normal page mentioning the sign-out control is not a sign-in page.
        let normal = PageContent(url: "https://classroom.google.com/u/2/h", title: "Home - Classroom",
                                 links: [], text: String(repeating: "Classes and work. Sign out. ", count: 200))
        XCTAssertFalse(SignInDetector.isSignInPage(normal))
    }

    // MARK: - Saved pages

    func testAPageCarryingASessionTokenIsNotSaved() {
        // Portal addresses often embed a session key, which expires and is a
        // credential besides.
        XCTAssertFalse(SavedPage.isReusable("https://portal.example.com/schedule?p=abc123&w=def456&sessionToken=xyz"))
        XCTAssertFalse(SavedPage.isReusable("https://portal.example.com/x?authKey=abc"))
        XCTAssertTrue(SavedPage.isReusable("https://classroom.google.com/u/2/a/not-turned-in/all"))
        XCTAssertFalse(SavedPage.isReusable("file:///etc/passwd"))
    }

    func testSavedPagesAreNamedSensibly() {
        XCTAssertEqual(SavedPage.suggestedName(for: "https://classroom.google.com/u/2/a/not-turned-in/all",
                                               title: "To-do - Classroom"), "To-do")
    }

    func testHandOutDateIsNotADeadline() throws {
        let lines = ["assignment", "Map Drills", "Summer Geography 2026", "Posted", "Thursday, Jun 11"]
        let now = try XCTUnwrap(date(2026, 8, 23))
        XCTAssertNil(DOMAssignmentReader.dueDate(in: lines, now: now, calendar: .current))
    }

    func testPostedOnOneLineWithItsDateIsNotADeadline() throws {
        let now = try XCTUnwrap(date(2026, 8, 23))
        XCTAssertNil(DOMAssignmentReader.dueDate(in: ["Reading List", "Posted Jun 11"],
                                                 now: now, calendar: .current))
    }

    func testARealDeadlineIsStillRead() throws {
        let lines = ["assignment", "Chapter One", "Honors ELA", "Wed, Aug 26, 11:59 PM"]
        let now = try XCTUnwrap(date(2026, 8, 23))
        let due = try XCTUnwrap(DOMAssignmentReader.dueDate(in: lines, now: now, calendar: .current))
        XCTAssertTrue(due.hasTime)
    }

    func testPostingDateIsSkippedInFavourOfTheDeadlineBelowIt() throws {
        let lines = ["Essay", "Posted", "Jun 11", "Due", "Fri, Sep 4"]
        let now = try XCTUnwrap(date(2026, 8, 23))
        let due = try XCTUnwrap(DOMAssignmentReader.dueDate(in: lines, now: now, calendar: .current))
        let parts = Calendar.current.dateComponents([.month, .day], from: due.date)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 4)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
}
