import Foundation
import CryptoKit
import Network
import AppKit

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

/// OAuth 2.0 for installed apps: PKCE plus a one-shot loopback listener.
///
/// Google redirects the browser back to `http://127.0.0.1:<random port>`, which
/// only this machine can reach, so no secret ever travels over the network in the
/// authorization step.
actor GoogleOAuth {
    static let shared = GoogleOAuth()

    static let scopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.student-submissions.me.readonly",
        "openid",
        "email",
    ]

    private let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    // MARK: - Stored tokens

    nonisolated var storedTokens: OAuthTokens? {
        guard let json = Keychain.get(Keychain.googleTokens),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    nonisolated func store(_ tokens: OAuthTokens?) {
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
            Keychain.remove(Keychain.googleTokens)
            return
        }
        Keychain.set(String(data: data, encoding: .utf8), for: Keychain.googleTokens)
    }

    nonisolated var isConnected: Bool { storedTokens != nil }

    nonisolated func signOut() {
        Keychain.remove(Keychain.googleTokens)
    }

    // MARK: - Sign in

    func signIn(clientID: String, clientSecret: String?) async throws -> OAuthTokens {
        guard !clientID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ImportError.notConfigured("Add your Google OAuth client ID in Settings first.")
        }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 24)

        let listener = try LoopbackListener()
        let redirectURI = "http://127.0.0.1:\(listener.port)"

        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else {
            listener.cancel()
            throw ImportError.badResponse("Could not build the sign-in URL.")
        }

        NSWorkspace.shared.open(authURL)

        let callback: LoopbackListener.Result
        do {
            callback = try await listener.waitForRedirect(timeout: 300)
        } catch {
            listener.cancel()
            throw error
        }
        listener.cancel()

        guard callback.state == state else {
            throw ImportError.badResponse("Sign-in response did not match the request. Please try again.")
        }
        if let error = callback.error {
            if error == "access_denied" {
                throw ImportError.accessBlocked(
                    "Google denied access. If this is a school account, the district may block outside apps — "
                    + "everything in Locker still works without syncing."
                )
            }
            throw ImportError.badResponse("Google returned an error: \(error)")
        }
        guard let code = callback.code else { throw ImportError.cancelled }

        return try await exchange(
            code: code, verifier: verifier, redirectURI: redirectURI,
            clientID: clientID, clientSecret: clientSecret
        )
    }

    private func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String,
        clientSecret: String?
    ) async throws -> OAuthTokens {
        var fields = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        if let clientSecret, !clientSecret.isEmpty { fields["client_secret"] = clientSecret }

        let response: TokenResponse = try await post(fields: fields)
        let tokens = OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
            scope: response.scope
        )
        store(tokens)
        return tokens
    }

    /// Returns a usable access token, refreshing it first when needed.
    func validAccessToken(clientID: String, clientSecret: String?) async throws -> String {
        guard let tokens = storedTokens else { throw ImportError.notConnected }
        guard tokens.isExpired else { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken else {
            signOut()
            throw ImportError.notConnected
        }

        var fields = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ]
        if let clientSecret, !clientSecret.isEmpty { fields["client_secret"] = clientSecret }

        do {
            let response: TokenResponse = try await post(fields: fields)
            let refreshed = OAuthTokens(
                accessToken: response.access_token,
                // Google only returns a refresh token on first consent; keep the old one.
                refreshToken: response.refresh_token ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
                scope: response.scope ?? tokens.scope
            )
            store(refreshed)
            return refreshed.accessToken
        } catch {
            // A revoked grant can never be refreshed; make the user sign in again
            // rather than failing silently on every sync.
            signOut()
            throw ImportError.notConnected
        }
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int?
        var scope: String?
    }

    private struct ErrorResponse: Decodable {
        var error: String?
        var error_description: String?
    }

    private func post<T: Decodable>(fields: [String: String]) async throws -> T {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ImportError.network("No response from Google.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))
                .flatMap { $0.error_description ?? $0.error } ?? "HTTP \(http.statusCode)"
            throw ImportError.badResponse("Google rejected the sign-in: \(detail)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - PKCE helpers

    nonisolated static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
    }

    nonisolated static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return base64URL(Data(bytes))
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
