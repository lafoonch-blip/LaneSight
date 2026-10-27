import Foundation
import Security

// MARK: - Session model
//
// The Supabase session the Mac API returns from /auth/signup | /auth/signin | /auth/refresh.
// `access_token` is a Supabase JWT (ES256) that the app sends as `Authorization: Bearer` on every
// authed Mac-API request. Tokens are persisted in the iOS Keychain (see `Keychain`), never UserDefaults.
struct AuthSession: Codable, Equatable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
    let user_id: String?
}

// MARK: - Auth client
//
// Talks to the Mac API's /auth/* endpoints only. These take email/password (or a refresh token) and
// carry NO Authorization header themselves. No Supabase keys ever live in the app — the Mac service
// mediates GoTrue. Errors are surfaced with user-facing text (bad credentials / taken email / network).
struct AuthClient {
    let baseURL: URL

    init(baseURLString: String) throws {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { throw APIError.badBaseURL(baseURLString) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw APIError.badBaseURL(baseURLString) }
        self.baseURL = url
    }

    func signup(email: String, password: String) async throws -> AuthSession {
        try await post("auth/signup", body: ["email": email, "password": password], context: .signup)
    }

    func signin(email: String, password: String) async throws -> AuthSession {
        try await post("auth/signin", body: ["email": email, "password": password], context: .signin)
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await post("auth/refresh", body: ["refresh_token": refreshToken], context: .refresh)
    }

    private func post(_ path: String, body: [String: String], context: AuthContext) async throws -> AuthSession {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No response from the server.")
        }
        if !(200...299).contains(http.statusCode) {
            throw AuthError.from(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "", context: context)
        }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            throw AuthError.network("Could not read the server's sign-in response.")
        }
    }
}

/// Which /auth/* call produced an error — lets us map status codes to the right user-facing message.
enum AuthContext { case signup, signin, refresh }

/// User-facing auth errors. `errorDescription` is safe to show directly in the auth UI.
enum AuthError: LocalizedError {
    case network(String)
    case badCredentials
    case emailTaken
    case weakPassword(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .network(let s): return "Network problem: \(s)"
        case .badCredentials: return "Incorrect email or password."
        case .emailTaken: return "That email is already registered. Try signing in instead."
        case .weakPassword(let s): return s
        case .server(let s): return s
        }
    }

    static func from(status: Int, body: String, context: AuthContext) -> AuthError {
        let lower = body.lowercased()
        switch context {
        case .signin:
            return status == 401 ? .badCredentials : .server(friendly(body, status: status))
        case .refresh:
            return .server("Your session could not be refreshed. Please sign in again.")
        case .signup:
            if lower.contains("already") || lower.contains("registered") { return .emailTaken }
            if lower.contains("password") && (lower.contains("length") || lower.contains("weak") || lower.contains("6")) {
                return .weakPassword("Password is too weak. Use at least 6 characters.")
            }
            if status == 401 { return .badCredentials }
            return .server(friendly(body, status: status))
        }
    }

    private static func friendly(_ body: String, status: Int) -> String {
        // Try to pull FastAPI's {"detail": "..."} out of the body; fall back to the raw text.
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = obj["detail"] as? String, !detail.isEmpty {
            return detail
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sign-in failed (HTTP \(status))." : String(trimmed.prefix(300))
    }
}

// MARK: - Keychain
//
// Minimal generic-password wrapper for the two auth tokens. Stored under this app's service so they
// survive relaunch but are cleared on sign out / account deletion. Never logged.
enum Keychain {
    private static let service = "com.lanesight.app.auth"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum Account {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let userId = "user_id"
    }
}
