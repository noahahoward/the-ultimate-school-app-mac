import XCTest
@testable import Locker

/// Portals list a class as a small stack of lines. The data here is invented,
/// but the shape is the one student portals actually print: a period number
/// heading each group, then name, catalogue code, teacher, room, and the term
/// that closes it.
final class ScheduleTextReaderTests: XCTestCase {

    /// One weekday of a two-semester timetable.
    var day: [String] {
        """
        DAY: M
        0
        Open Period
        1
        WORLD LANGUAGE I
        WLG250 / 01
        AVERY LINDQVIST
        108
        S1
        WORLD LANGUAGE II
        WLG251 / 01
        AVERY LINDQVIST
        108
        S2
        2
        HEALTH AND FITNESS I
        PED158 / 04
        JORDAN OKONKWO
        GYM
        S1
        HUMAN GEOGRAPHY II
        SOC158 / 02
        RILEY THACKERAY
        227
        S2
        3
        LIFE SCIENCE I
        SCI250 / 08
        MORGAN ELLSWORTH
        219
        S1
        LIFE SCIENCE II
        SCI251 / 08
        MORGAN ELLSWORTH
        219
        S2
        5
        OFF CAMPUS RELEASE SEM 1
        ZZZ901 / 05
        S1
        """.split(whereSeparator: \.isNewline).map(String.init)
    }

    var found: [ClassDraft] { ScheduleTextReader.classes(from: day) }

    func testEveryClassIsFound() {
        XCTAssertEqual(found.count, 7, "got: \(found.map(\.name))")
    }

    func testNamesAreNotClipped() {
        XCTAssertTrue(found.contains { $0.name == "HEALTH AND FITNESS I" })
        XCTAssertTrue(found.contains { $0.name == "OFF CAMPUS RELEASE SEM 1" })
    }

    func testPeriodsComeFromTheHeadingAboveTheGroup() {
        let periods = Dictionary(uniqueKeysWithValues: found.map { ("\($0.name)|\($0.semester)", $0.period) })
        XCTAssertEqual(periods["WORLD LANGUAGE I|1"], 1)
        XCTAssertEqual(periods["HUMAN GEOGRAPHY II|2"], 2)
        XCTAssertEqual(periods["LIFE SCIENCE I|1"], 3)
        XCTAssertEqual(periods["OFF CAMPUS RELEASE SEM 1|1"], 5)
    }

    func testBothHalvesOfTheYearAreKeptSeparately() {
        let science = found.filter { $0.name.hasPrefix("LIFE SCIENCE") }
        XCTAssertEqual(science.count, 2)
        XCTAssertEqual(Set(science.map(\.semester)), [1, 2])
        XCTAssertEqual(Set(science.map(\.period)), [3])
    }

    func testTeachersAndRoomsSurvive() {
        let science = found.first { $0.name == "LIFE SCIENCE I" }
        XCTAssertEqual(science?.teacher, "MORGAN ELLSWORTH")
        XCTAssertEqual(science?.room, "219")
        let fitness = found.first { $0.name == "HEALTH AND FITNESS I" }
        XCTAssertEqual(fitness?.room, "GYM")
    }

    func testACourseNameIsNotMistakenForATeacher() {
        // "LIFE SCIENCE I" is two capitalised words plus a numeral, exactly like
        // a person's name apart from the numeral.
        XCTAssertFalse(ScheduleTextReader.isPersonName("LIFE SCIENCE I"))
        XCTAssertFalse(ScheduleTextReader.isPersonName("HEALTH AND FITNESS I"))
        XCTAssertTrue(ScheduleTextReader.isPersonName("MORGAN ELLSWORTH"))
        XCTAssertTrue(ScheduleTextReader.isPersonName("Avery Lindqvist"))
    }

    func testAFreePeriodIsNotAClass() {
        // "Open Period" has no course code, so it is a gap in the day.
        XCTAssertFalse(found.contains { $0.name.lowercased().contains("open period") })
    }

    func testAClassWithNoTeacherOrRoomStillCounts() {
        let release = found.first { $0.name == "OFF CAMPUS RELEASE SEM 1" }
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.teacher, "")
        XCTAssertEqual(release?.room, "")
    }

    func testTheSameWeekRepeatedIsNotSevenTimetables() {
        // Portals print the identical block for every weekday.
        let week = day + day + day + day + day
        XCTAssertEqual(ScheduleTextReader.classes(from: week).count, found.count)
    }

    // MARK: - Shape, not portal

    func testTermMarkersInTheFormsPortalsUse() {
        XCTAssertEqual(ScheduleTextReader.termMarker("S1"), 1)
        XCTAssertEqual(ScheduleTextReader.termMarker("Semester 2"), 2)
        XCTAssertEqual(ScheduleTextReader.termMarker("Full Year"), 0)
        XCTAssertNil(ScheduleTextReader.termMarker("SPANISH"))
    }

    func testCourseCodesAreRecognisedByShape() {
        XCTAssertTrue(ScheduleTextReader.isCourseCode("MAT220 / 08"))
        XCTAssertTrue(ScheduleTextReader.isCourseCode("ENG-171"))
        XCTAssertFalse(ScheduleTextReader.isCourseCode("MORGAN ELLSWORTH"))
        XCTAssertFalse(ScheduleTextReader.isCourseCode("219"))
    }

    func testAPageThatIsNotATimetableYieldsNothing() {
        let noise = ["Welcome back", "S1", "Your account", "Sign out"]
        XCTAssertTrue(ScheduleTextReader.classes(from: noise).isEmpty)
    }
}
