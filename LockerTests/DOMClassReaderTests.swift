import XCTest
@testable import Locker

/// Reading the page instead of photographing it. The point is the names: the
/// screen clips them, the page does not.
final class DOMClassReaderTests: XCTestCase {

    func link(_ text: String, href: String, card: String = "", label: String = "") -> PageContent.Link {
        PageContent.Link(href: href, text: text, label: label, card: card.isEmpty ? text : card)
    }

    /// A Classroom classes page as the browser reports it.
    var classroomPage: PageContent {
        PageContent(
            url: "https://classroom.google.com/u/2/h/st",
            title: "Home - Classroom",
            links: [
                link("2026 Summer Homework: Honors English 9",
                     href: "https://classroom.google.com/c/NzM4OTk",
                     card: "2026 Summer Homework: Honors English 9\nSerena Sturgill"),
                link("BIOLOGY I-3-S1",
                     href: "https://classroom.google.com/c/ODQxMjM",
                     card: "BIOLOGY I-3-S1\n3\nBenjamin Cook"),
                link("ALG 2 For Pre-Calc",
                     href: "https://classroom.google.com/c/OTU1NTU",
                     card: "ALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nKate Barry"),
                // Not a course: one assignment inside a course.
                link("Summer Homework Assignment 2026",
                     href: "https://classroom.google.com/c/ODQxMjM/a/MTIz/details"),
                link("Settings", href: "https://classroom.google.com/u/2/settings"),
            ],
            text: "Classes\n2026 Summer Homework: Honors English 9\nBIOLOGY I-3-S1"
        )
    }

    var found: [ClassDraft] { DOMClassReader.classes(from: classroomPage) }

    func testOnlyCoursesAreTreatedAsClasses() {
        XCTAssertEqual(found.count, 3, "got: \(found.map(\.name))")
        XCTAssertFalse(found.contains { $0.name.contains("Assignment") })
        XCTAssertFalse(found.contains { $0.name == "Settings" })
    }

    func testNamesComeThroughWhole() {
        // This is the whole point: the screen shows "2026 Summer Homew…".
        XCTAssertTrue(found.contains { $0.name == "2026 Summer Homework: Honors English 9" })
    }

    func testPeriodAndTeacherComeFromTheCardAroundTheLink() {
        let biology = found.first { $0.name == "BIOLOGY I-3-S1" }
        XCTAssertEqual(biology?.period, 3)
        XCTAssertEqual(biology?.semester, 1)
        XCTAssertEqual(biology?.teacher, "Benjamin Cook")

        let algebra = found.first { $0.name == "ALG 2 For Pre-Calc" }
        XCTAssertEqual(algebra?.period, 4)
        XCTAssertEqual(algebra?.teacher, "Kate Barry")
    }

    func testCourseLinksAreToldFromEverythingElse() {
        XCTAssertTrue(DOMClassReader.isCourseLink("https://classroom.google.com/c/NzM4OTk"))
        XCTAssertTrue(DOMClassReader.isCourseLink("https://canvas.instructure.com/courses/12345"))
        XCTAssertFalse(DOMClassReader.isCourseLink("https://classroom.google.com/c/NzM4OTk/a/MTIz/details"))
        XCTAssertFalse(DOMClassReader.isCourseLink("https://classroom.google.com/u/2/settings"))
        XCTAssertFalse(DOMClassReader.isCourseLink("not a url"))
    }

    func testTheSameCourseLinkedTwiceIsOneClass() {
        var page = classroomPage
        page.links.append(link("BIOLOGY I-3-S1", href: "https://classroom.google.com/c/ODQxMjM"))
        XCTAssertEqual(DOMClassReader.classes(from: page).count, 3)
    }

    func testAPageWithNoCoursesYieldsNothing() {
        let page = PageContent(url: "https://example.com", title: "Nothing",
                               links: [link("Home", href: "https://example.com")], text: "Hello")
        XCTAssertTrue(DOMClassReader.classes(from: page).isEmpty)
    }

    func testALabelIsUsedWhenTheLinkTextIsEmpty() {
        let page = PageContent(url: "u", title: "t", links: [
            PageContent.Link(href: "https://classroom.google.com/c/AAA", text: "",
                             label: "World History Honors", card: "World History Honors\nMr. Dunn")
        ], text: "")
        XCTAssertEqual(DOMClassReader.classes(from: page).first?.name, "World History Honors")
    }

    // MARK: - Telling a switched-off setting from a dead end

    func testABrowserWithJavaScriptDisabledSaysHowToFixIt() {
        // The exact complaint Brave returns.
        let message = "Brave Browser got an error: Executing JavaScript through AppleScript is turned off."
        let failure = BrowserDOM.failure(for: message, browser: "Brave Browser")
        guard case .javaScriptDisabled = failure else { return XCTFail("expected the fixable case") }
        XCTAssertTrue(failure.errorDescription?.contains("Allow JavaScript from Apple Events") == true)
    }

    func testAnyOtherProblemIsReportedPlainly() {
        let failure = BrowserDOM.failure(for: "The browser didn't answer.", browser: "Safari")
        guard case .unreadable = failure else { return XCTFail("expected the generic case") }
    }
}
