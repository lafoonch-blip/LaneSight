import Foundation

/// Wraps one array element so a single malformed element decodes to nil instead of failing the whole array
/// (used by APIClient.decodeLossyArray — DEC-086 lossy list decode).
private struct LossyElement<U: Decodable>: Decodable {
    let value: U?
    init(from decoder: Decoder) throws { value = try? U(from: decoder) }
}

enum APIError: LocalizedError {
    case badBaseURL(String)
    case http(status: Int, body: String)
    case transport(String)
    case decoding(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badBaseURL(let s): return "Invalid API base URL: \(s)"
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "HTTP \(status)\(trimmed.isEmpty ? "" : ": \(trimmed.prefix(300))")"
        case .transport(let s): return "Network error: \(s)"
        case .decoding(let s): return "Could not read server response: \(s)"
        case .unauthorized: return "Your session expired. Please sign in again."
        }
    }
}

/// Small async URLSession client. Sends the base URL from Settings on every request. The normal app
/// path authenticates with `Authorization: Bearer <access_token>` (a Supabase JWT); `/health` and
/// `/auth/*` carry no auth. `X-Dev-User` is sent ONLY when the Dev-panel "use dev user" toggle is on
/// (`devUser` non-nil) — never by default. On a 401 the client refreshes the token once and retries.
struct APIClient {
    let baseURL: URL
    /// Supabase access token for `Authorization: Bearer`. Nil when using the dev-user path.
    let accessToken: String?
    /// Dev-user id for `X-Dev-User`. Non-nil ONLY when the explicit Dev-panel toggle is on.
    let devUser: String?
    /// Refreshes the access token on a 401 and returns the new token (or nil → caller should sign out).
    let refresher: (@Sendable () async -> String?)?

    init(baseURLString: String, accessToken: String?, devUser: String?,
         refresher: (@Sendable () async -> String?)? = nil) throws {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { throw APIError.badBaseURL(baseURLString) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw APIError.badBaseURL(baseURLString) }
        self.baseURL = url
        self.accessToken = accessToken
        self.devUser = devUser
        self.refresher = refresher
    }

    // MARK: request plumbing

    private func makeRequest(_ path: String, method: String = "GET", auth: Bool = true) -> URLRequest {
        // A path carrying a query string ("me/stats?view=throw") must NOT go through appendingPathComponent,
        // which percent-encodes the "?" and yields a 404. Build those by string; plain paths keep the
        // component API (which correctly encodes each segment).
        let url: URL
        if path.contains("?") {
            let base = baseURL.absoluteString
            url = URL(string: base + (base.hasSuffix("/") ? "" : "/") + path) ?? baseURL.appendingPathComponent(path)
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if auth { applyAuth(&req) }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    /// Attaches the real Bearer token when authenticated; otherwise the dev-user header only when the
    /// Dev-panel toggle explicitly supplied one. If neither is present the server replies 401 (fail visibly).
    private func applyAuth(_ req: inout URLRequest) {
        if let accessToken {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else if let devUser, !devUser.isEmpty {
            req.setValue(devUser, forHTTPHeaderField: "X-Dev-User")
        }
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
    private func sendRaw(_ req: URLRequest, allowRefresh: Bool = true) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           allowRefresh, accessToken != nil, let refresher {
            if let newToken = await refresher() {
                var retry = req
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await sendRaw(retry, allowRefresh: false)
            }
            throw APIError.unauthorized
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Multipart body send with the same 401 → refresh → retry-once behavior as `sendRaw`.
    private func uploadRaw(_ req: URLRequest, body: Data,
                           delegate: URLSessionTaskDelegate, allowRefresh: Bool = true) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: req, from: body, delegate: delegate)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401,
           allowRefresh, accessToken != nil, let refresher {
            if let newToken = await refresher() {
                var retry = req
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await uploadRaw(retry, body: body, delegate: delegate, allowRefresh: false)
            }
            throw APIError.unauthorized
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

    /// Fetches one KEY POSITIONS still for the Form card (GET /shots/{id}/frame/{key}). Owner-scoped,
    /// bowler-cropped JPEG. Returns nil on a 404 (the pose engine didn't export that key) so the caller
    /// shows an honest "not found" placeholder instead of a guessed frame.
    func shotFrame(shotId: String, key: String) async throws -> Data? {
        do {
            return try await sendRaw(makeRequest("shots/\(shotId)/frame/\(key)"))
        } catch APIError.http(let status, _) where status == 404 {
            return nil
        }
    }

    func score() async throws -> ScoreResponse {
        try await send(makeRequest("me/score"), as: ScoreResponse.self)
    }

    func focus() async throws -> FocusResponse {
        try await send(makeRequest("me/focus"), as: FocusResponse.self)
    }

    /// Score-parts detail inputs for the Stats · Score screen (GET /me/score/breakdown).
    func scoreBreakdown() async throws -> ScoreBreakdown {
        try await send(makeRequest("me/score/breakdown"), as: ScoreBreakdown.self)
    }

    func scoreHistory() async throws -> [ScoreResponse] {
        try await send(makeRequest("me/score/history"), as: [ScoreResponse].self)
    }

    // MARK: sessions

    func listSessions() async throws -> [SessionRow] {
        try await send(makeRequest("sessions"), as: [SessionRow].self)
    }

    /// Standalone upload analyses for Lab › Uploads (GET /me/uploads, DEC-055). Each row opens its result.
    /// Lossy decode (DEC-086): one malformed row — e.g. a new failure field an older build doesn't know —
    /// must not blank the whole list, so rows decode independently and bad ones are dropped.
    func listUploads() async throws -> [UploadRow] {
        let data = try await sendRaw(makeRequest("me/uploads"))
        return try decodeLossyArray(data, as: UploadRow.self)
    }

    /// Decodes a JSON array element-by-element, skipping any element that fails to decode. Throws only if
    /// the payload isn't a JSON array at all (a real server/transport problem worth surfacing).
    private func decodeLossyArray<T: Decodable>(_ data: Data, as type: T.Type) throws -> [T] {
        do {
            return try JSONDecoder().decode([LossyElement<T>].self, from: data).compactMap(\.value)
        } catch {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) [\(snippet.prefix(200))]")
        }
    }

    /// Home Recent activity (GET /me/activity). Server-scoped to practice sessions, achievement unlocks
    /// and tier changes (DEC-055).
    func activity() async throws -> [ActivityItem] {
        try await send(makeRequest("me/activity"), as: [ActivityItem].self)
    }

    func createSessionFull(mode: String, lanePair: String?, oilPatternId: String?) async throws -> SessionRow {
        var req = makeRequest("sessions", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["mode": mode]
        if let lanePair, !lanePair.isEmpty { body["lane_pair"] = lanePair }
        if let oilPatternId, !oilPatternId.isEmpty { body["oil_pattern_id"] = oilPatternId }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, as: SessionRow.self)
    }

    func endSession(_ sid: String) async throws -> EndSessionResponse {
        try await send(makeRequest("sessions/\(sid)/end", method: "POST"), as: EndSessionResponse.self)
    }

    /// Per-shot rows for the live Session screen (GET /sessions/{id}/shots).
    func sessionShots(_ sid: String) async throws -> [SessionShotRow] {
        try await send(makeRequest("sessions/\(sid)/shots"), as: [SessionShotRow].self)
    }

    /// Session aggregates for the Active Session rings + Session summary (GET /sessions/{id}/summary):
    /// per-metric mean/spread + a consistency repeatability score.
    func lastSetup() async throws -> LastSetup {
        try await send(makeRequest("me/last-setup"), as: LastSetup.self)
    }

    func formSessionSummary(_ sid: String) async throws -> FormSessionSummary {
        try await send(makeRequest("sessions/\(sid)/form-summary"), as: FormSessionSummary.self)
    }

    func sessionSummary(_ sid: String) async throws -> SessionSummary {
        try await send(makeRequest("sessions/\(sid)/summary"), as: SessionSummary.self)
    }

    // MARK: stats

    func stats(view: String, range: String?) async throws -> StatsResponse {
        var path = "me/stats?view=\(view)"
        if let range, !range.isEmpty { path += "&range=\(range)" }
        return try await send(makeRequest(path), as: StatsResponse.self)
    }

    /// Per-metric detail for the Stats metric-detail screens (GET /me/stats/metric/{metric}).
    func metricDetail(_ metric: String) async throws -> MetricDetailResponse {
        try await send(makeRequest("me/stats/metric/\(metric)"), as: MetricDetailResponse.self)
    }

    /// Per-ball / per-oil-pattern rollup for the Stats · Equipment tab (GET /me/stats/equipment).
    func equipmentStats() async throws -> EquipmentStats {
        try await send(makeRequest("me/stats/equipment"), as: EquipmentStats.self)
    }

    // MARK: achievements

    func achievements() async throws -> AchievementsResponse {
        try await send(makeRequest("me/achievements"), as: AchievementsResponse.self)
    }

    func achievementDetail(_ id: String) async throws -> AchievementDetail {
        try await send(makeRequest("me/achievements/\(id)"), as: AchievementDetail.self)
    }

    /// Replaces the showcase/pursuit pin set (PUT /me/achievements/pins). Returns the stored pins.
    @discardableResult
    func setPins(_ pins: [[String: Any]]) async throws -> [AchievementPin] {
        var req = makeRequest("me/achievements/pins", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pins": pins])
        return (try await send(req, as: PinsResponse.self)).pins ?? []
    }

    // MARK: notifications

    func notifications(undelivered: Bool) async throws -> [AppNotification] {
        try await send(makeRequest("me/notifications?undelivered=\(undelivered ? 1 : 0)"),
                       as: [AppNotification].self)
    }

    func markNotificationDelivered(_ id: String) async throws {
        try await sendRaw(makeRequest("me/notifications/\(id)/delivered", method: "POST"))
    }

    func dismissNotification(_ id: String) async throws {
        try await sendRaw(makeRequest("me/notifications/\(id)/dismiss", method: "POST"))
    }

    // MARK: account

    func deleteAccount() async throws {
        try await sendRaw(makeRequest("me", method: "DELETE"))
    }

    /// Multipart upload of a Photos/Files clip (POST /uploads). Standalone analysis (DEC-055): no
    /// session — the server stamps source=upload and leaves session_id null, so it never appears in
    /// Recent sessions / activity and never feeds Stats, the Score, tiers or achievements. Reports
    /// upload progress (0...1) on the main actor.
    func uploadClip(fileURL: URL,
                    metadata: ShotMetadata,
                    progress: @escaping @MainActor (Double) -> Void) async throws -> CreateShotResponse {
        let boundary = "LaneSight-\(UUID().uuidString)"
        var req = makeRequest("uploads", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw APIError.transport("Could not read the selected clip: \(error.localizedDescription)")
        }

        var body = Data()
        func appendString(_ s: String) { body.append(s.data(using: .utf8)!) }
        let filename = fileURL.lastPathComponent

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n")
        appendString(metadata.jsonString())
        appendString("\r\n")

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: video/quicktime\r\n\r\n")
        body.append(fileData)
        appendString("\r\n")
        appendString("--\(boundary)--\r\n")

        let progressDelegate = UploadProgressDelegate { fraction in
            Task { @MainActor in progress(fraction) }
        }

        let data = try await uploadRaw(req, body: body, delegate: progressDelegate)
        do {
            return try JSONDecoder().decode(CreateShotResponse.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) [\(snippet.prefix(200))]")
        }
    }

    // MARK: storage-backed analysis (large clips bypass the API request-size cap)

    /// Ask the API for a signed, one-shot Supabase Storage upload target. POST /uploads/signed-url.
    func signedUploadURL() async throws -> UploadTarget {
        try await send(makeRequest("uploads/signed-url", method: "POST"), as: UploadTarget.self)
    }

    /// PUT the clip bytes straight to Supabase Storage. The signed URL carries its own token, so this does
    /// NOT go through the API (no API base URL, no Authorization header) and has no request-size cap.
    func putClipToStorage(uploadURL: String, fileURL: URL,
                          progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let url = URL(string: uploadURL) else {
            throw APIError.transport("The upload URL from the server was invalid.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.timeoutInterval = 600               // large clip over a slow bowling-center connection
        let delegate = UploadProgressDelegate { fraction in
            Task { @MainActor in progress(fraction) }
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: req, fromFile: fileURL, delegate: delegate)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Analyze a clip already uploaded to Storage. POST /shots/analyze. `sessionId` nil → standalone upload;
    /// set → a shot in that live session. Phase-1 backend runs the CV INLINE, so this request blocks for the
    /// whole analysis — hence the long client timeout (treat as async in the UI regardless).
    func analyzeFromStorage(storagePath: String, sessionId: String?,
                            metadata: ShotMetadata,
                            clientTimings: [String: Double]? = nil) async throws -> CreateShotResponse {
        var req = makeRequest("shots/analyze", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600
        let metaObj = (try? JSONSerialization.jsonObject(
            with: Data(metadata.jsonString().utf8))) ?? [:]
        var body: [String: Any] = ["storage_path": storagePath, "metadata": metaObj]
        if let sessionId { body["session_id"] = sessionId }
        if let clientTimings { body["client_timings"] = clientTimings }   // DEC-092 P0: phone-side stage times
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, as: CreateShotResponse.self)
    }

    // MARK: shots

    /// Records the sensor answer for a shot (No / Yes + the user's sensor). PATCH /shots/{id}.
    func patchShotSensor(shotId: String, sensorUsed: Bool, sensorId: String?) async throws {
        var req = makeRequest("shots/\(shotId)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["sensor_used": sensorUsed]
        body["sensor_id"] = sensorId ?? NSNull()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await sendRaw(req)
    }

    /// Reports the user's leave for a shot whose pins the CV couldn't read (GUARDRAILS 3.7 C.2,
    /// NextShotStates "PINS NOT READ"). The server stores it as source=user, recomputes insights and
    /// returns the updated shot record so the card can re-render from the new `state`. `leave` is one of
    /// strike | 10 | 4-7 | split | other; `pins` is an explicit standing-pin list when the user picked pins.
    func reportPins(shotId: String, leave: String?, pins: [Int]?, strike: Bool) async throws -> ShotResponse {
        var req = makeRequest("shots/\(shotId)/pins", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["strike": strike]
        if let leave { body["leave"] = leave }
        if let pins { body["pins"] = pins }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, as: ShotResponse.self)
    }

    // MARK: spot check (advisory)

    func spotCheck(framing: [String: Any]) async throws -> SpotCheckResponse {
        var req = makeRequest("spot-check", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["framing": framing])
        return try await send(req, as: SpotCheckResponse.self)
    }

    // MARK: profile & sensors

    func getProfile() async throws -> Profile {
        try await send(makeRequest("me/profile"), as: Profile.self)
    }

    func putProfile(_ fields: [String: Any]) async throws -> Profile {
        var req = makeRequest("me/profile", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await send(req, as: Profile.self)
    }

    /// DEC-084: whether the user has asked to be notified when Coaching launches.
    func getCoachingNotify() async throws -> Bool {
        struct R: Decodable { let coaching_launch: Bool? }
        return (try await send(makeRequest("me/notify"), as: R.self)).coaching_launch ?? false
    }

    /// DEC-084: record the "Notify me when Coaching is ready" choice (one launch notification later).
    func setCoachingNotify() async throws {
        var req = makeRequest("me/notify", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["coaching_launch": true])
        _ = try await sendRaw(req)
    }

    /// DEC-087: start an email change. The server calls Supabase Auth, which emails a confirmation link;
    /// the address isn't changed until the user confirms. Returns the user-facing message to show.
    func putEmail(_ email: String) async throws -> String {
        var req = makeRequest("me/email", method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        struct R: Decodable { let message: String?; let email_pending: String? }
        return (try await send(req, as: R.self)).message ?? "Check your new email to confirm the change."
    }

    /// Pulls a {"detail":{"field","message"}} validation error (DEC-087) out of a 400 so the UI can show the
    /// server's reason inline on the offending field. Returns nil for any other error.
    static func fieldError(from error: Error) -> (field: String, message: String)? {
        guard case APIError.http(let status, let body) = error, status == 400,
              let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = obj["detail"] as? [String: Any],
              let field = detail["field"] as? String, let message = detail["message"] as? String
        else { return nil }
        return (field, message)
    }

    // MARK: profile photo (handoff G)

    /// The processed 512px JPEG avatar, or nil when none is set (404). Needs auth, so it can't be an
    /// AsyncImage(url:) — fetch the bytes and build a UIImage caller-side.
    func avatarData() async throws -> Data? {
        do {
            return try await sendRaw(makeRequest("me/avatar"))
        } catch APIError.http(let status, _) where status == 404 {
            return nil
        }
    }

    @discardableResult
    func uploadAvatar(_ data: Data, mime: String = "image/jpeg") async throws -> AvatarStatus {
        let boundary = "LaneSight-\(UUID().uuidString)"
        var req = makeRequest("me/avatar", method: "PUT")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func s(_ x: String) { body.append(x.data(using: .utf8)!) }
        s("--\(boundary)\r\n")
        s("Content-Disposition: form-data; name=\"file\"; filename=\"avatar\"\r\n")
        s("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        s("\r\n--\(boundary)--\r\n")
        let resp = try await uploadRaw(req, body: body, delegate: UploadProgressDelegate { _ in })
        return try JSONDecoder().decode(AvatarStatus.self, from: resp)
    }

    @discardableResult
    func deleteAvatar() async throws -> AvatarStatus {
        let data = try await sendRaw(makeRequest("me/avatar", method: "DELETE"))
        return try JSONDecoder().decode(AvatarStatus.self, from: data)
    }

    func listSensors() async throws -> [Sensor] {
        try await send(makeRequest("me/sensors"), as: [Sensor].self)
    }

    func addSensor(name: String, isDefault: Bool) async throws -> Sensor {
        var req = makeRequest("me/sensors", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "default": isDefault])
        return try await send(req, as: Sensor.self)
    }

    func deleteSensor(_ id: String) async throws {
        try await sendRaw(makeRequest("me/sensors/\(id)", method: "DELETE"))
    }

    // MARK: catalog & oil

    func catalogBalls(query: String?) async throws -> [CatalogBall] {
        var path = "catalog/balls"
        if let q = query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            path += "?q=\(enc)"
        }
        return try await send(makeRequest(path), as: [CatalogBall].self)
    }

    func oilPatterns() async throws -> [OilPattern] {
        try await send(makeRequest("oil-patterns"), as: [OilPattern].self)
    }

    // MARK: arsenal (GET/POST /me/arsenal, PATCH /me/arsenal/{id})

    func getArsenal() async throws -> [ArsenalBall] {
        try await send(makeRequest("me/arsenal"), as: [ArsenalBall].self)
    }

    /// Adds a ball. Pass `ballModelId` for a catalog ball (optionally with `nickname`) OR `name` for a
    /// custom ball. Optional config fields and `makeCurrent` match the live contract.
    func addBall(ballModelId: String? = nil,
                 name: String? = nil,
                 nickname: String? = nil,
                 weightLb: Double? = nil,
                 colorDesc: String? = nil,
                 layoutSystem: String? = nil,
                 layout: String? = nil,
                 surface: String? = nil,
                 makeCurrent: Bool = false) async throws -> ArsenalBall {
        var req = makeRequest("me/arsenal", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let ballModelId, !ballModelId.isEmpty { body["ball_model_id"] = ballModelId }
        if let name, !name.isEmpty { body["name"] = name }
        if let nickname, !nickname.isEmpty { body["nickname"] = nickname }
        if let weightLb { body["weight_lb"] = weightLb }
        if let colorDesc, !colorDesc.isEmpty { body["color_desc"] = colorDesc }
        if let layoutSystem, !layoutSystem.isEmpty { body["layout_system"] = layoutSystem }
        if let layout, !layout.isEmpty { body["layout"] = layout }
        if let surface, !surface.isEmpty { body["surface"] = surface }
        if makeCurrent { body["make_current"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, as: ArsenalBall.self)
    }

    /// Patches an arsenal row. Pass any subset of the editable fields as a `[String: Any]` patch.
    @discardableResult
    func updateBall(id: String, patch: [String: Any]) async throws -> ArsenalBall {
        var req = makeRequest("me/arsenal/\(id)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: patch)
        return try await send(req, as: ArsenalBall.self)
    }

    /// Makes `id` the one current ball (server unsets the others). PATCH is_current:true.
    @discardableResult
    func setCurrentBall(id: String) async throws -> ArsenalBall {
        try await updateBall(id: id, patch: ["is_current": true])
    }

    func feedbackFull(sessionId: String, rating: Int, tags: [String], text: String?, diagnostics: Bool) async throws {
        var req = makeRequest("sessions/\(sessionId)/feedback", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["rating": rating, "tags": tags, "diagnostics": diagnostics]
        if let text, !text.isEmpty { body["text"] = text }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await sendRaw(req)
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

        let data = try await uploadRaw(req, body: body, delegate: progressDelegate)
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
