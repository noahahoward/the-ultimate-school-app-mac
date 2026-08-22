import Foundation

/// The hard slots a screenshot can fill.
///
/// Every value is *verbatim text copied from the screenshot*, never an
/// interpretation. Empty means "the screenshot didn't show this" — the model is
/// never asked to work anything out, only to say which text belongs in which slot.
/// Turning these strings into dates and numbers is done in Swift, in `FieldParsing`.
struct ExtractedFields: Equatable, Sendable {
    var title = ""
    var teacher = ""
    var className = ""
    var dueDateText = ""
    var assignedDateText = ""
    var pointsText = ""
    var statusText = ""
    var attachments: [String] = []
    /// The one field the model writes itself rather than copies.
    var summary = ""

    /// Slots that must appear word-for-word in the screenshot to be trusted.
    /// `summary` is excluded because it is written, not copied.
    var verbatimSlots: [(name: String, value: String)] {
        [
            ("Title", title),
            ("Teacher", teacher),
            ("Class", className),
            ("Due date", dueDateText),
            ("Assigned date", assignedDateText),
            ("Points", pointsText),
            ("Status", statusText),
        ] + attachments.enumerated().map { ("Attachment \($0.offset + 1)", $0.element) }
    }
}

/// A slot that was thrown away because it wasn't actually on screen.
struct RejectedField: Equatable, Sendable {
    var name: String
    var value: String
    var reason: String
}

/// What the importer proposes to create, after validation and parsing.
/// Nothing here is written to the database until the student confirms it.
struct ImportDraft: Equatable, Sendable {
    var title = ""
    var teacher = ""
    var className = ""
    var summary = ""
    var attachments: [String] = []

    var dueAt: Date?
    var dueDateText = ""
    var assignedAt: Date?
    var assignedDateText = ""
    var maxPoints: Double?
    var pointsText = ""
    var isTurnedIn: Bool?
    var statusText = ""

    var type: AssignmentType = .homework

    /// Everything the model claimed that the screenshot didn't back up.
    var rejected: [RejectedField] = []

    var isUsable: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
}
