import XCTest
@testable import Locker

/// Built from the real JSON a Google Classroom page returned, links and all.
/// Every quirk here is one the live page actually has: an account prefix in the
/// address, the same course linked several times over, a one-letter avatar in
/// front of the name, and a sidebar blob that begins with whichever class is
/// listed first.
final class DOMRealPageTests: XCTestCase {

    var page: PageContent {
        PageContent(
            url: "https://classroom.google.com/u/2/h/st",
            title: "Home - Classroom",
            links: [
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgyOTA0OTY2", text: "F\nFOUND HEALTH/FIT I-2-S1\n2", label: "FOUND HEALTH/FIT I-2-S1 2", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgyOTA0OTY2", text: "FOUND HEALTH/FIT I-2-S1\n2", label: "", card: "FOUND HEALTH/FIT I-2-S1\n2\nZachary Myers\nOpen your work for \"FOUND HEALTH/FIT I-2-S1\"\nOpen folder for \"FOUND HEALTH/FIT I-2-S1 2\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgyOTA0OTY2", text: "FFOUND HEALTH/FIT I-2-S12", label: "FOUND HEALTH/FIT I-2-S1 2", card: "EnrolledTo-doFFOUND HEALTH/FIT I-2-S12AAP HUMAN GEO I-8-S18AALG 2 For Pre-CalcPer 4 - Mrs. BarryBBIOLOGY I-3-S1322026 Summer Homework: Honors ELA 9SSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMzk0MzAw", text: "A\nAP HUMAN GEO I-8-S1\n8", label: "AP HUMAN GEO I-8-S1 8", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMzk0MzAw", text: "", label: "AP HUMAN GEO I-8-S1", card: "assignment\nSyllabus\nClass\nAP HUMAN GEO I-8-S1\nAP HUMAN GEO I-8-S1\nLearn with Gemini\nFri, Aug 28, 11:59 PM\nSyllabus"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMzk0MzAw", text: "AP HUMAN GEO I-8-S1\n8", label: "", card: "AP HUMAN GEO I-8-S1\n8\nTodd Baker\nDue Friday\nSyllabus\nOpen your work for \"AP HUMAN GEO I-8-S1\"\nOpen folder for \"AP HUMAN GEO I-8-S1 8\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzNjAxNDI1", text: "A\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry", label: "ALG 2 For Pre-Calc Per 4 - Mrs. Barry", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzNjAxNDI1", text: "ALG 2 For Pre-Calc\nPer 4 - Mrs. Barry", label: "", card: "ALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nKate Barry\nOpen your work for \"ALG 2 For Pre-Calc\"\nOpen folder for \"ALG 2 For Pre-Calc Per 4 - Mrs. Barry\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzNjAxNDI1", text: "AALG 2 For Pre-CalcPer 4 - Mrs. Barry", label: "ALG 2 For Pre-Calc Per 4 - Mrs. Barry", card: "EnrolledTo-doFFOUND HEALTH/FIT I-2-S12AAP HUMAN GEO I-8-S18AALG 2 For Pre-CalcPer 4 - Mrs. BarryBBIOLOGY I-3-S1322026 Summer Homework: Honors ELA 9SSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMDU3MDU4", text: "B\nBIOLOGY I-3-S1\n3", label: "BIOLOGY I-3-S1 3", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMDU3MDU4", text: "BIOLOGY I-3-S1\n3", label: "", card: "BIOLOGY I-3-S1\n3\nBenjamin Cook\nOpen your work for \"BIOLOGY I-3-S1\"\nOpen folder for \"BIOLOGY I-3-S1 3\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODcyMjgzMDU3MDU4", text: "BBIOLOGY I-3-S13", label: "BIOLOGY I-3-S1 3", card: "EnrolledTo-doFFOUND HEALTH/FIT I-2-S12AAP HUMAN GEO I-8-S18AALG 2 For Pre-CalcPer 4 - Mrs. BarryBBIOLOGY I-3-S1322026 Summer Homework: Honors ELA 9SSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3MjA2MDE1MDUy", text: "2\n2026 Summer Homework: Honors ELA 9", label: "2026 Summer Homework: Honors ELA 9", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3MjA2MDE1MDUy", text: "", label: "2026 Summer Homework: Honors ELA 9", card: "assignment\nSummer Homework Assignment 2026\nClass\n2026 Summer Homework: Honors ELA 9\n2026 Summer Homework: Honors ELA 9\nLearn with Gemini\nWed, Aug 26, 11:59 PM\nSummer Homework Assignment 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3MjA2MDE1MDUy", text: "2026 Summer Homework: Honors ELA 9", label: "", card: "2026 Summer Homework: Honors ELA 9\nSerena Sturgill\nDue Wednesday\nSummer Homework Assignment 2026\nOpen your work for \"2026 Summer Homework: Honors ELA 9\"\nOpen folder for \"2026 Summer Homework: Honors ELA 9\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3NzI5MzY2NTky", text: "S\nSummer Homework AP Human Geo 2026", label: "Summer Homework AP Human Geo 2026", card: "To-do\nF\nFOUND HEALTH/FIT I-2-S1\n2\nA\nAP HUMAN GEO I-8-S1\n8\nA\nALG 2 For Pre-Calc\nPer 4 - Mrs. Barry\nB\nBIOLOGY I-3-S1\n3\n2\n2026 Summer Homework: Honors ELA 9\nS\nSummer Homework AP Human Geo 2026"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3NzI5MzY2NTky", text: "Summer Homework AP Human Geo 2026", label: "", card: "Summer Homework AP Human Geo 2026\nTodd Baker\nOpen your work for \"Summer Homework AP Human Geo 2026\"\nOpen folder for \"Summer Homework AP Human Geo 2026\" in Google Drive\nmore_vert\nMore options"),
            .init(href: "https://classroom.google.com/u/2/c/ODY3NzI5MzY2NTky", text: "SSummer Homework AP Human Geo 2026", label: "Summer Homework AP Human Geo 2026", card: "EnrolledTo-doFFOUND HEALTH/FIT I-2-S12AAP HUMAN GEO I-8-S18AALG 2 For Pre-CalcPer 4 - Mrs. BarryBBIOLOGY I-3-S1322026 Summer Homework: Honors ELA 9SSummer Homework AP Human Geo 2026"),
            ],
            text: ""
        )
    }

    var found: [ClassDraft] { DOMClassReader.classes(from: page) }

    func testEveryEnrolledClassIsFound() {
        XCTAssertEqual(found.count, 6, "got: \(found.map(\.name))")
    }

    func testNamesArriveWholeRatherThanClipped() {
        let names = Set(found.map(\.name))
        // The screen shows "2026 Summer Homew..."; the page knows better.
        XCTAssertTrue(names.contains("2026 Summer Homework: Honors ELA 9"))
        XCTAssertTrue(names.contains("Summer Homework AP Human Geo 2026"))
        XCTAssertTrue(names.contains("FOUND HEALTH/FIT I-2-S1"))
    }

    func testTheAvatarLetterIsNotPartOfTheName() {
        // Link text begins "B\nBIOLOGY I-3-S1\n3".
        XCTAssertFalse(found.contains { $0.name.hasPrefix("B ") || $0.name == "BBIOLOGY I-3-S13" })
        XCTAssertTrue(found.contains { $0.name == "BIOLOGY I-3-S1" })
    }

    func testTeachersStayWithTheirOwnClass() {
        let teachers = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.teacher) })
        XCTAssertEqual(teachers["FOUND HEALTH/FIT I-2-S1"], "Zachary Myers")
        XCTAssertEqual(teachers["BIOLOGY I-3-S1"], "Benjamin Cook")
        XCTAssertEqual(teachers["ALG 2 For Pre-Calc"], "Kate Barry")
        XCTAssertEqual(teachers["2026 Summer Homework: Honors ELA 9"], "Serena Sturgill")
    }

    func testPeriodsAndSemestersComeFromTheClassItself() {
        let periods = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.period) })
        let semesters = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.semester) })

        XCTAssertEqual(periods["BIOLOGY I-3-S1"], 3)
        XCTAssertEqual(periods["AP HUMAN GEO I-8-S1"], 8)
        // Read from "Per 4 - Mrs. Barry", and it has no semester code.
        XCTAssertEqual(periods["ALG 2 For Pre-Calc"], 4)
        XCTAssertEqual(semesters["ALG 2 For Pre-Calc"], 0)
        // A course with neither must not inherit them from the class above it.
        XCTAssertNil(periods["Summer Homework AP Human Geo 2026"] ?? nil)
        XCTAssertEqual(semesters["Summer Homework AP Human Geo 2026"], 0)
    }

    func testTheSameCourseLinkedManyTimesIsOneClass() {
        let names = found.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicates: \(names)")
    }

    func testAnAccountPrefixInTheAddressIsStillACourse() {
        XCTAssertEqual(DOMClassReader.courseID(in: "https://classroom.google.com/u/2/c/ODcyMjgyOTA0OTY2"),
                       "ODcyMjgyOTA0OTY2")
        XCTAssertNil(DOMClassReader.courseID(in: "https://classroom.google.com/u/2/c/ODcy/a/ODc1/details"))
        XCTAssertNil(DOMClassReader.courseID(in: "https://classroom.google.com/u/2/s"))
        XCTAssertNil(DOMClassReader.courseID(in: "https://drive.google.com/drive/folders/abc"))
    }
}
