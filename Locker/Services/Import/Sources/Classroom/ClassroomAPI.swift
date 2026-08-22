import Foundation

/// Wire types for the Google Classroom REST API, plus the mapping into Locker's
/// source-agnostic import DTOs.
enum ClassroomDTO {

    struct CourseList: Decodable {
        var courses: [Course]?
        var nextPageToken: String?
    }

    struct Course: Decodable {
        var id: String
        var name: String?
        var section: String?
        var room: String?
        var courseState: String?
        var alternateLink: String?
        var teacherFolder: Folder?
    }

    struct Folder: Decodable {
        var title: String?
    }

    struct CourseWorkList: Decodable {
        var courseWork: [CourseWork]?
        var nextPageToken: String?
    }

    struct CourseWork: Decodable {
        var id: String
        var title: String?
        var description: String?
        var dueDate: YMD?
        var dueTime: HMS?
        var maxPoints: Double?
        var workType: String?
        var state: String?
        var alternateLink: String?
    }

    struct YMD: Decodable {
        var year: Int?
        var month: Int?
        var day: Int?
    }

    struct HMS: Decodable {
        var hours: Int?
        var minutes: Int?
        var seconds: Int?
    }

    struct SubmissionList: Decodable {
        var studentSubmissions: [Submission]?
        var nextPageToken: String?
    }

    struct Submission: Decodable {
        var id: String
        var courseWorkId: String?
        var state: String?
        var late: Bool?
        var assignedGrade: Double?
    }

    struct UserInfo: Decodable {
        var email: String?
    }

    struct APIError: Decodable {
        struct Body: Decodable {
            var code: Int?
            var message: String?
            var status: String?
        }
        var error: Body?
    }
}

extension ClassroomDTO.Course {
    var importedClass: ImportedClass {
        ImportedClass(
            externalID: id,
            name: name ?? "Untitled course",
            teacher: "",
            room: room ?? "",
            section: section ?? "",
            period: Self.period(from: section),
            url: alternateLink
        )
    }

    /// Many teachers name sections "Period 3" or "P3"; pull the number out when they do.
    static func period(from section: String?) -> Int? {
        guard let section = section?.lowercased() else { return nil }
        let markers = ["period ", "per ", "p"]
        for marker in markers {
            guard let range = section.range(of: marker) else { continue }
            let digits = section[range.upperBound...].prefix { $0.isNumber }
            if let value = Int(digits), (1...12).contains(value) { return value }
        }
        return nil
    }
}

extension ClassroomDTO.CourseWork {
    /// Google reports due dates in UTC. An entry with no `dueTime` is an all-day
    /// deadline, so it is anchored to the local calendar date instead.
    func dueDateAndTime(calendar: Calendar = .current) -> (date: Date?, hasTime: Bool) {
        guard let dueDate, let year = dueDate.year, let month = dueDate.month, let day = dueDate.day else {
            return (nil, false)
        }

        guard let dueTime, (dueTime.hours ?? 0) != 0 || (dueTime.minutes ?? 0) != 0 else {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            return (calendar.date(from: comps), false)
        }

        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = dueTime.hours ?? 0
        comps.minute = dueTime.minutes ?? 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return (utcCalendar.date(from: comps), true)
    }

    /// Classroom has no notion of "test" vs "homework", so the title is the only
    /// signal available. The same keyword table the quick-add box uses reads it.
    var inferredType: AssignmentType {
        let text = (title ?? "").lowercased()
        let keywords: [(String, AssignmentType)] = [
            ("final exam", .test), ("midterm", .test), ("exam", .test), ("test", .test),
            ("quiz", .quiz),
            ("lab", .lab),
            ("essay", .essay), ("paper", .essay), ("write-up", .essay),
            ("project", .project),
            ("presentation", .presentation), ("speech", .presentation),
            ("read", .reading), ("chapter", .reading),
        ]
        for (needle, type) in keywords where text.contains(needle) { return type }
        if workType == "SHORT_ANSWER_QUESTION" || workType == "MULTIPLE_CHOICE_QUESTION" { return .quiz }
        return .homework
    }

    func importedAssignment(courseID: String, isSubmitted: Bool?, calendar: Calendar = .current) -> ImportedAssignment {
        let due = dueDateAndTime(calendar: calendar)
        return ImportedAssignment(
            externalID: id,
            classExternalID: courseID,
            title: (title ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines),
            details: description ?? "",
            dueAt: due.date,
            hasDueTime: due.hasTime,
            type: inferredType,
            isSubmitted: isSubmitted,
            maxPoints: maxPoints,
            url: alternateLink
        )
    }
}

/// Read-only Google Classroom client.
struct ClassroomAPI {
    var accessToken: String
    var session: URLSession = .shared

    private let base = URL(string: "https://classroom.googleapis.com/v1/")!

    func currentEmail() async throws -> String? {
        let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
        let info: ClassroomDTO.UserInfo = try await get(url)
        return info.email
    }

    func activeCourses() async throws -> [ClassroomDTO.Course] {
        try await paginate { pageToken in
            var components = URLComponents(url: base.appending(path: "courses"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "studentId", value: "me"),
                .init(name: "courseStates", value: "ACTIVE"),
                .init(name: "pageSize", value: "100"),
                pageToken.map { URLQueryItem(name: "pageToken", value: $0) },
            ].compactMap { $0 }
            let page: ClassroomDTO.CourseList = try await get(components.url!)
            return (page.courses ?? [], page.nextPageToken)
        }
    }

    func courseWork(courseID: String) async throws -> [ClassroomDTO.CourseWork] {
        try await paginate { pageToken in
            var components = URLComponents(
                url: base.appending(path: "courses/\(courseID)/courseWork"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                .init(name: "pageSize", value: "100"),
                .init(name: "courseWorkStates", value: "PUBLISHED"),
                pageToken.map { URLQueryItem(name: "pageToken", value: $0) },
            ].compactMap { $0 }
            let page: ClassroomDTO.CourseWorkList = try await get(components.url!)
            return (page.courseWork ?? [], page.nextPageToken)
        }
    }

    /// All of this student's submissions for a course, keyed by coursework id.
    func submissions(courseID: String) async throws -> [String: ClassroomDTO.Submission] {
        let all: [ClassroomDTO.Submission] = try await paginate { pageToken in
            var components = URLComponents(
                url: base.appending(path: "courses/\(courseID)/courseWork/-/studentSubmissions"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                .init(name: "userId", value: "me"),
                .init(name: "pageSize", value: "100"),
                pageToken.map { URLQueryItem(name: "pageToken", value: $0) },
            ].compactMap { $0 }
            let page: ClassroomDTO.SubmissionList = try await get(components.url!)
            return (page.studentSubmissions ?? [], page.nextPageToken)
        }

        var byCourseWork: [String: ClassroomDTO.Submission] = [:]
        for submission in all {
            guard let key = submission.courseWorkId else { continue }
            byCourseWork[key] = submission
        }
        return byCourseWork
    }

    // MARK: - Plumbing

    private func paginate<T>(_ page: (String?) async throws -> ([T], String?)) async throws -> [T] {
        var results: [T] = []
        var token: String?
        for _ in 0..<20 {
            let (items, next) = try await page(token)
            results.append(contentsOf: items)
            guard let next, !next.isEmpty else { break }
            token = next
        }
        return results
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ImportError.network("Couldn't reach Google Classroom: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ImportError.network("No response from Google Classroom.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ImportError.badResponse("Google Classroom sent back something unexpected.")
        }
    }

    static func error(status: Int, data: Data) -> ImportError {
        let message = (try? JSONDecoder().decode(ClassroomDTO.APIError.self, from: data))?.error?.message

        switch status {
        case 401:
            return .notConnected
        case 403:
            return .accessBlocked(
                message.map { "Google Classroom denied access: \($0)" }
                ?? "Google Classroom denied access. School accounts often block outside apps — "
                + "ask the district's admin to allow it, or keep using Locker without syncing."
            )
        case 404:
            return .badResponse("That course is no longer available in Google Classroom.")
        case 429:
            return .network("Google is rate limiting requests. Try syncing again in a minute.")
        default:
            return .badResponse(message ?? "Google Classroom returned HTTP \(status).")
        }
    }
}
