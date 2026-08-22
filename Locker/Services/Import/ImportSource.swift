import Foundation

/// A class as an external system describes it.
public struct ImportedClass: Equatable, Sendable {
    public var externalID: String
    public var name: String
    public var teacher: String
    public var room: String
    public var section: String
    public var period: Int?
    public var url: String?
    /// Only some sources know when a class meets; nil means "leave the local schedule alone".
    public var meetingWeekdays: Set<Int>?
    public var startMinutes: Int?
    public var endMinutes: Int?

    public init(
        externalID: String,
        name: String,
        teacher: String = "",
        room: String = "",
        section: String = "",
        period: Int? = nil,
        url: String? = nil,
        meetingWeekdays: Set<Int>? = nil,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil
    ) {
        self.externalID = externalID
        self.name = name
        self.teacher = teacher
        self.room = room
        self.section = section
        self.period = period
        self.url = url
        self.meetingWeekdays = meetingWeekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }
}

/// An assignment as an external system describes it.
public struct ImportedAssignment: Equatable, Sendable {
    public var externalID: String
    public var classExternalID: String
    public var title: String
    public var details: String
    public var dueAt: Date?
    public var hasDueTime: Bool
    public var type: AssignmentType
    /// Nil when the source doesn't say; only `true` ever marks something done locally.
    public var isSubmitted: Bool?
    public var maxPoints: Double?
    public var url: String?

    public init(
        externalID: String,
        classExternalID: String,
        title: String,
        details: String = "",
        dueAt: Date? = nil,
        hasDueTime: Bool = false,
        type: AssignmentType = .homework,
        isSubmitted: Bool? = nil,
        maxPoints: Double? = nil,
        url: String? = nil
    ) {
        self.externalID = externalID
        self.classExternalID = classExternalID
        self.title = title
        self.details = details
        self.dueAt = dueAt
        self.hasDueTime = hasDueTime
        self.type = type
        self.isSubmitted = isSubmitted
        self.maxPoints = maxPoints
        self.url = url
    }
}

public struct ImportPayload: Equatable, Sendable {
    public var classes: [ImportedClass]
    public var assignments: [ImportedAssignment]

    public init(classes: [ImportedClass] = [], assignments: [ImportedAssignment] = []) {
        self.classes = classes
        self.assignments = assignments
    }
}

/// Anything Locker can pull school data from. Google Classroom implements this today;
/// a Skyward source would slot in here without touching the models, merge, or UI.
public protocol ImportSource: AnyObject {
    var sourceID: SourceID { get }
    var displayName: String { get }
    /// What the student has to set up before `connect()` can work, if anything.
    var setupHint: String { get }
    var isConfigured: Bool { get }
    var isConnected: Bool { get }
    /// Shown in Settings, e.g. the signed-in address.
    var accountDescription: String { get }

    func connect() async throws
    func disconnect()
    func fetch() async throws -> ImportPayload
}

public enum ImportError: LocalizedError {
    case notConfigured(String)
    case notConnected
    case cancelled
    case accessBlocked(String)
    case network(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let hint): hint
        case .notConnected: "Not connected yet."
        case .cancelled: "Sign-in was cancelled."
        case .accessBlocked(let detail): detail
        case .network(let detail): detail
        case .badResponse(let detail): detail
        }
    }
}
