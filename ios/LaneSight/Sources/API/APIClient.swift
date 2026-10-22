import Foundation

enum APIError: LocalizedError {
    case badBaseURL(String)
    case http(status: Int, body: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badBaseURL(let s): return "Invalid API base URL: \(s)"
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "HTTP \(status)\(trimmed.isEmpty ? "" : ": \(trimmed.prefix(300))")"
        case .transport(let s): return "Network error: \(s)"
        case .decoding(let s): return "Could not read server response: \(s)"
        }
    }
}

/// Small async URLSession client. Injects `X-Dev-User` and the base URL from Settings on every
/// request except `/health`. No bearer token in this slice (API dev mode).
struct APIClient {
    let baseURL: URL
    let devUser: String

    init(baseURLString: String, devUser: String) throws {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { throw APIError.badBaseURL(baseURLString) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw APIError.badBaseURL(baseURLString) }
        self.baseURL = url
        self.devUser = devUser
    }

    // MARK: request plumbing

    private func makeRequest(_ path: String, method: String = "GET", auth: Bool = true) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if auth { req.setValue(devUser, forHTTPHeaderField: "X-Dev-User") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendRaw(req)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) [\(snippet.prefix(200))]")
        }
    }

    @discardableResult
    private func sendRaw(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: endpoints

    func health() async throws -> HealthResponse {
        try await send(makeRequest("health", auth: false), as: HealthResponse.self)
    }

    func createSession(mode: String = "practice") async throws -> SessionResponse {
        var req = makeRequest("sessions", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
        return try await send(req, as: SessionResponse.self)
    }

    func job(_ id: String) async throws -> JobResponse {
        try await send(makeRequest("jobs/\(id)"), as: JobResponse.self)
    }

    func shot(_ id: String) async throws -> ShotResponse {
        try await send(makeRequest("shots/\(id)"), as: ShotResponse.self)
    }

    func score() async throws -> ScoreResponse {
        try await send(makeRequest("me/score"), as: ScoreResponse.self)
    }

    func feedback(sessionId: String, rating: Int, text: String?) async throws {
        var req = makeRequest("sessions/\(sessionId)/feedback", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["rating": rating, "tags": [String]()]
        if let text, !text.isEmpty { body["text"] = text }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await sendRaw(req)
    }

    /// Multipart upload of the `.mov` plus the `metadata` JSON string. Reports upload progress
    /// (0...1) via `progress`, invoked on the main actor.
    func uploadShot(sessionId: String,
                    fileURL: URL,
                    metadata: ShotMetadata,
                    progress: @escaping @MainActor (Double) -> Void) async throws -> CreateShotResponse {
        let boundary = "LaneSight-\(UUID().uuidString)"
        var req = makeRequest("sessions/\(sessionId)/shots", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw APIError.transport("Could not read recorded clip: \(error.localizedDescription)")
        }

        var body = Data()
        func appendString(_ s: String) { body.append(s.data(using: .utf8)!) }
        let filename = fileURL.lastPathComponent

        // metadata form field
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n")
        appendString(metadata.jsonString())
        appendString("\r\n")

        // file field
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: video/quicktime\r\n\r\n")
        body.append(fileData)
        appendString("\r\n")
        appendString("--\(boundary)--\r\n")

        let progressDelegate = UploadProgressDelegate { fraction in
            Task { @MainActor in progress(fraction) }
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: req, from: body, delegate: progressDelegate)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(CreateShotResponse.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) [\(snippet.prefix(200))]")
        }
    }
}

/// Reports upload progress. Marked `nonisolated` so its URLSession delegate callbacks (delivered on
/// URLSession's own queue) satisfy the protocol without MainActor isolation.
nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
