import Foundation

/// Posts a bowler's shot note + quick tags to the retained feedback store (DEC-058 / DEC-059):
/// `POST /feedback` with `source: "shot_note"`. Autosave is achieved by resending the SAME `id`
/// (the server updates the row in place). This lives in Result/ and talks to the API directly —
/// rather than extending the shared `APIClient` — so the Shot card can be rebuilt without touching
/// files other agents are editing. It reuses the app's live auth exactly like `APIClient`:
/// a real `Authorization: Bearer <jwt>` normally, or `X-Dev-User` only when the Dev-panel toggle is on,
/// and a single 401 → refresh → retry.
///
/// Nothing here fabricates data: it only sends what the bowler typed/selected, keyed to this shot.
@MainActor
struct ShotNoteClient {
    let model: AppModel

    /// Saves (or re-saves, same `id`) a shot note. `tags` are the pressed quick-tag labels; `text` is the
    /// free-text. Links the note to the current shot/session so it can be compared with the measurements.
    func save(noteId: String, shotId: String, text: String, tags: [String], isUpload: Bool) async throws {
        var body: [String: Any] = [
            "id": noteId,
            "source": "shot_note",
            "shot_id": shotId,
            "tags": tags,
            "capture_mode": model.captureMode,
            "is_upload": isUpload,
        ]
        if let sid = model.activeSessionId { body["session_id"] = sid }
        // Send text even when empty: clearing the field is a legitimate autosave edit.
        body["text"] = text
        try await post(path: "feedback", json: body)
    }

    // MARK: request plumbing (mirrors APIClient's auth + 401-retry, scoped to this one endpoint)

    private func baseURL() throws -> URL {
        var s = model.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { throw APIError.badBaseURL(model.apiBaseURL) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw APIError.badBaseURL(model.apiBaseURL) }
        return url
    }

    private func post(path: String, json: [String: Any]) async throws {
        let url = try baseURL().appendingPathComponent(path)
        let data = try JSONSerialization.data(withJSONObject: json)
        try await send(url: url, body: data, allowRefresh: true)
    }

    private func send(url: URL, body: Data, allowRefresh: Bool) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body
        applyAuth(&req)

        let respData: Data, response: URLResponse
        do {
            (respData, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           allowRefresh, !model.useDevUser, model.session != nil {
            if let newToken = await model.refreshAccessToken() {
                var retry = req
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (_, r2) = try await URLSession.shared.data(for: retry)
                if let h2 = r2 as? HTTPURLResponse, !(200...299).contains(h2.statusCode) {
                    throw APIError.http(status: h2.statusCode, body: "")
                }
                return
            }
            throw APIError.unauthorized
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: respData, encoding: .utf8) ?? "")
        }
    }

    /// Real Bearer token on the normal path; the dev-user header only when the Dev-panel toggle supplied one.
    private func applyAuth(_ req: inout URLRequest) {
        if !model.useDevUser, let token = model.session?.access_token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if model.useDevUser, !model.devUser.isEmpty {
            req.setValue(model.devUser, forHTTPHeaderField: "X-Dev-User")
        }
    }
}
