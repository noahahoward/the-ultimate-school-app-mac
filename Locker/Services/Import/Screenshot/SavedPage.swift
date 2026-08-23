import Foundation

/// A page the student wants to read again.
///
/// Kept because the useful pages are few and fixed — a to-do list, a schedule —
/// and hunting for the right tab every time is the sort of friction that stops
/// a thing being used at all.
struct SavedPage: Codable, Hashable, Identifiable, Sendable {
    var id: String { url }
    var url: String
    var name: String
    var lastReadAt: Date?
    /// What was found last time, so the entry can say whether it is worth
    /// keeping rather than just sitting there.
    var lastResult: String

    init(url: String, name: String, lastReadAt: Date? = nil, lastResult: String = "") {
        self.url = url
        self.name = name
        self.lastReadAt = lastReadAt
        self.lastResult = lastResult
    }

    /// A readable name for a page, from its address.
    static func suggestedName(for url: String, title: String) -> String {
        let cleanTitle = title
            .replacingOccurrences(of: " - Classroom", with: "")
            .replacingOccurrences(of: " - Google Classroom", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !cleanTitle.isEmpty { return cleanTitle }
        return URL(string: url)?.host ?? "Saved page"
    }

    /// Whether an address is one Locker can usefully re-read.
    ///
    /// Only http(s), and never a page carrying what looks like a session token
    /// in its address — those expire, and storing one is storing a credential.
    static func isReusable(_ url: String) -> Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return false }
        let query = (parsed.query ?? "").lowercased()
        let secrets = ["token", "auth", "session", "sso", "ticket", "password"]
        return !secrets.contains { query.contains($0) }
    }
}
