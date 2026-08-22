import XCTest
@testable import Locker

/// Google Classroom's JSON, decoded and mapped the way a real sync would.
final class ClassroomSourceTests: XCTestCase {

    let calendar = TestClock.calendar

    func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Courses

    func testCourseMapsToImportedClass() throws {
        let course = try decode("""
        {"id":"7788","name":"Biology I","section":"Period 3","room":"204",
         "courseState":"ACTIVE","alternateLink":"https://classroom.google.com/c/7788"}
        """, as: ClassroomDTO.Course.self)

        let imported = course.importedClass
        XCTAssertEqual(imported.externalID, "7788")
        XCTAssertEqual(imported.name, "Biology I")
        XCTAssertEqual(imported.room, "204")
        XCTAssertEqual(imported.period, 3)
        XCTAssertEqual(imported.url, "https://classroom.google.com/c/7788")
    }

    func testPeriodIsPulledFromCommonSectionNamings() {
        XCTAssertEqual(ClassroomDTO.Course.period(from: "Period 5"), 5)
        XCTAssertEqual(ClassroomDTO.Course.period(from: "per 2"), 2)
        XCTAssertEqual(ClassroomDTO.Course.period(from: "P7"), 7)
        XCTAssertNil(ClassroomDTO.Course.period(from: "Honors"))
        XCTAssertNil(ClassroomDTO.Course.period(from: nil))
    }

    func testCourseWithoutANameStillImports() throws {
        let course = try decode(#"{"id":"1"}"#, as: ClassroomDTO.Course.self)
        XCTAssertEqual(course.importedClass.name, "Untitled course")
    }

    // MARK: - Due dates

    func testDueDateWithoutATimeIsAnAllDayLocalDate() throws {
        let work = try decode("""
        {"id":"a1","title":"Reading","dueDate":{"year":2026,"month":9,"day":18}}
        """, as: ClassroomDTO.CourseWork.self)

        let due = work.dueDateAndTime(calendar: calendar)
        XCTAssertFalse(due.hasTime)
        XCTAssertEqual(due.date, TestClock.date(2026, 9, 18))
    }

    func testDueTimeIsConvertedFromUTC() throws {
        // Google reports 23:59 UTC, which is 6:59 PM in the test timezone.
        let work = try decode("""
        {"id":"a1","title":"Essay","dueDate":{"year":2026,"month":9,"day":18},
         "dueTime":{"hours":23,"minutes":59}}
        """, as: ClassroomDTO.CourseWork.self)

        let due = work.dueDateAndTime(calendar: calendar)
        XCTAssertTrue(due.hasTime)
        XCTAssertEqual(due.date, TestClock.date(2026, 9, 18, 18, 59))
    }

    func testMissingDueDateMeansNoDeadline() throws {
        let work = try decode(#"{"id":"a1","title":"Optional practice"}"#, as: ClassroomDTO.CourseWork.self)
        let due = work.dueDateAndTime(calendar: calendar)
        XCTAssertNil(due.date)
        XCTAssertFalse(due.hasTime)
    }

    // MARK: - Type inference

    func testTypeIsInferredFromTheTitle() throws {
        func type(_ title: String, workType: String = "ASSIGNMENT") throws -> AssignmentType {
            try decode("""
            {"id":"a1","title":"\(title)","workType":"\(workType)"}
            """, as: ClassroomDTO.CourseWork.self).inferredType
        }

        XCTAssertEqual(try type("Unit 3 Test"), .test)
        XCTAssertEqual(try type("Midterm review"), .test)
        XCTAssertEqual(try type("Vocab Quiz 2"), .quiz)
        XCTAssertEqual(try type("Osmosis Lab"), .lab)
        XCTAssertEqual(try type("Persuasive essay"), .essay)
        XCTAssertEqual(try type("Read chapter 4"), .reading)
        XCTAssertEqual(try type("Problem set 5"), .homework)
        XCTAssertEqual(try type("Warm up", workType: "MULTIPLE_CHOICE_QUESTION"), .quiz)
    }

    // MARK: - Whole item

    func testCourseWorkMapsToImportedAssignment() throws {
        let work = try decode("""
        {"id":"cw9","title":"  Cell diagram  ","description":"Label every organelle",
         "dueDate":{"year":2026,"month":9,"day":18},"maxPoints":25,
         "alternateLink":"https://classroom.google.com/c/7788/a/cw9"}
        """, as: ClassroomDTO.CourseWork.self)

        let imported = work.importedAssignment(courseID: "7788", isSubmitted: true, calendar: calendar)
        XCTAssertEqual(imported.externalID, "cw9")
        XCTAssertEqual(imported.classExternalID, "7788")
        XCTAssertEqual(imported.title, "Cell diagram")
        XCTAssertEqual(imported.details, "Label every organelle")
        XCTAssertEqual(imported.maxPoints, 25)
        XCTAssertEqual(imported.isSubmitted, true)
    }

    func testSubmissionListDecodes() throws {
        let list = try decode("""
        {"studentSubmissions":[{"id":"s1","courseWorkId":"cw9","state":"TURNED_IN","late":false}]}
        """, as: ClassroomDTO.SubmissionList.self)
        XCTAssertEqual(list.studentSubmissions?.first?.state, "TURNED_IN")
    }

    // MARK: - Errors

    func testErrorsAreTranslatedIntoSomethingReadable() {
        let forbidden = ClassroomAPI.error(
            status: 403,
            data: Data(#"{"error":{"code":403,"message":"The caller does not have permission"}}"#.utf8)
        )
        guard case .accessBlocked(let text) = forbidden else { return XCTFail("expected accessBlocked") }
        XCTAssertTrue(text.contains("permission"))

        guard case .notConnected = ClassroomAPI.error(status: 401, data: Data()) else {
            return XCTFail("401 should mean we need to sign in again")
        }
        guard case .network = ClassroomAPI.error(status: 429, data: Data()) else {
            return XCTFail("429 should be treated as a transient network problem")
        }
    }
}
