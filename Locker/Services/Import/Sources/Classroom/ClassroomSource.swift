import Foundation

/// Google Classroom as an `ImportSource`.
///
/// Everything Classroom-specific stops here: the merge layer and the UI only ever
/// see `ImportedClass` / `ImportedAssignment`, which is what makes adding another
/// system later a matter of writing one more of these.
final class ClassroomSource: ImportSource {

    let sourceID = SourceID.googleClassroom
    let displayName = "Google Classroom"
    let setupHint = "Paste an OAuth client ID from Google Cloud Console to connect."

    /// Read from settings each time so editing the client ID takes effect immediately.
    var clientIDProvider: () -> String
    var connectedEmailHandler: (String?) -> Void = { _ in }

    private let oauth = GoogleOAuth.shared

    init(clientIDProvider: @escaping () -> String) {
        self.clientIDProvider = clientIDProvider
    }

    private var clientID: String {
        clientIDProvider().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var clientSecret: String? {
        Keychain.get(Keychain.googleClientSecret)
    }

    var isConfigured: Bool { !clientID.isEmpty }
    var isConnected: Bool { oauth.isConnected }
    var accountDescription: String { oauth.storedTokens == nil ? "" : "Signed in" }

    func connect() async throws {
        guard isConfigured else { throw ImportError.notConfigured(setupHint) }
        _ = try await oauth.signIn(clientID: clientID, clientSecret: clientSecret)

        // Best effort: knowing the address makes Settings much clearer, but a
        // failure here must not block a sign-in that otherwise worked.
        if let token = try? await oauth.validAccessToken(clientID: clientID, clientSecret: clientSecret),
           let email = try? await ClassroomAPI(accessToken: token).currentEmail() {
            connectedEmailHandler(email)
        }
    }

    func disconnect() {
        oauth.signOut()
        connectedEmailHandler(nil)
    }

    func fetch() async throws -> ImportPayload {
        guard isConfigured else { throw ImportError.notConfigured(setupHint) }
        guard isConnected else { throw ImportError.notConnected }

        let token = try await oauth.validAccessToken(clientID: clientID, clientSecret: clientSecret)
        let api = ClassroomAPI(accessToken: token)

        let courses = try await api.activeCourses()
        var classes: [ImportedClass] = []
        var assignments: [ImportedAssignment] = []

        for course in courses {
            classes.append(course.importedClass)

            let work = try await api.courseWork(courseID: course.id)
            // Submissions are a separate call; without them nothing would ever
            // show as turned in. A failure here degrades to "not submitted"
            // rather than failing the whole sync.
            let submissions = (try? await api.submissions(courseID: course.id)) ?? [:]

            for item in work {
                let state = submissions[item.id]?.state
                let isSubmitted: Bool? = state.map { $0 == "TURNED_IN" || $0 == "RETURNED" }
                assignments.append(item.importedAssignment(courseID: course.id, isSubmitted: isSubmitted))
            }
        }

        return ImportPayload(classes: classes, assignments: assignments)
    }
}
