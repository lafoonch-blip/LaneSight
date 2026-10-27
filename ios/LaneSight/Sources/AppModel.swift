import Foundation
import SwiftUI
import Combine
import UIKit

/// Progress of the capture -> upload -> analyze -> result pipeline.
enum PipelineState: Equatable {
    case idle
    case creatingSession
    case trimming                          // on-device clip trim to the shot window (live capture)
    case uploading(Double)                 // 0...1
    case analyzing(state: String, timings: [String: Double])
    case fetching
    case done
    case failed(String)
}

/// The data shown on the result screen. Everything here is fetched live from the API.
struct ShotResult: Equatable {
    var shotId: String
    var metrics: [(String, Metric)]
    var score: ScoreResponse
    var footer: ShotFooter?              // score_delta + achievement_nudges from the analyze job
    var suggestedTarget: SuggestedTarget?  // server-computed next-shot target (drives "Apply this move")
    var recommendation: Recommendation?    // the actionable move rec (reason/direction label)

    // 3.7 Next-shot state machine (GUARDRAILS 3.7 C.7/F). The shot card renders from `insightsState`:
    // move | low_confidence_move | strike_repeat | execution_miss | pins_unknown | no_reliable_data.
    var insightsState: String?
    var insightsConfidence: String?
    var insightsNote: String?
    // Capture-quality banner (B): shown above "Target vs actual" when the far lane was limited.
    var captureFarLaneLimited: Bool = false
    var captureReason: String?
    // Uploaded clip (DEC-055): no Score / achievement block, show the upload footer instead.
    var isUpload: Bool = false

    // Form-analysis routing. When `isForm` is true the result is rendered by FormCardView (no entry
    // board / score / "Apply this move"). `formView` is the detected camera angle; `formStatus` is the
    // record's top-level status ("ok" | "unavailable" — the latter means the pose backend couldn't run).
    var isForm: Bool = false
    var formView: String?
    var formStatus: String?
    var formVersion: String?
    var formFPS: Double?

    /// 1-based shot number within its session, for the "Shot N" header. Nil for an uploaded clip that
    /// isn't part of a live session (no honest ordinal → the header falls back to "Shot").
    var shotNumber: Int? = nil

    // Form fundamentals v1 (DEC-057): the after_form_analyzed footer fields carried from the shot record.
    var keyFrames: [String] = []
    var events: [String: Double] = [:]
    var timingCheckpoints: [String: TimingCheckpoint] = [:]
    var measuredPositions: [String: MeasuredPosition] = [:]
    var swingTiming: SwingTiming?
    var coachingCues: CoachingCues?
    var formFocus: FormFocus?
    var formFooter: FormFooter?

    static func == (lhs: ShotResult, rhs: ShotResult) -> Bool {
        lhs.shotId == rhs.shotId && lhs.metrics.map(\.0) == rhs.metrics.map(\.0)
            && lhs.footer == rhs.footer && lhs.suggestedTarget == rhs.suggestedTarget
            && lhs.isForm == rhs.isForm && lhs.formStatus == rhs.formStatus
            && lhs.formView == rhs.formView && lhs.keyFrames == rhs.keyFrames
            && lhs.formFooter == rhs.formFooter
    }
}

/// Where the app is in the auth → profile → app gate.
enum AuthGate: Equatable {
    case unauthenticated     // no session → Welcome / Sign in / Create account
    case needsProfile        // signed in but profile incomplete → profile setup → add ball
    case ready               // signed in with a complete profile → the tab app
}

@MainActor
final class AppModel: ObservableObject {
    // Persisted settings
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Keys.baseURL) } }
    @Published var devUser: String { didSet { defaults.set(devUser, forKey: Keys.devUser) } }
    /// Dev-only escape hatch: send `X-Dev-User` instead of a real Bearer token. OFF by default; the
    /// normal app path ALWAYS uses real auth. Toggled only from the clearly-labeled Dev panel control.
    @Published var useDevUser: Bool { didSet { defaults.set(useDevUser, forKey: Keys.useDevUser) } }
    @Published var handed: String { didSet { defaults.set(handed, forKey: Keys.handed) } }
    @Published var speedUnit: String { didSet { defaults.set(speedUnit, forKey: Keys.speedUnit) } }   // "mph" | "kmh"
    @Published var speakAdjustments: Bool { didSet { defaults.set(speakAdjustments, forKey: Keys.speak) } }
    /// Preferred capture frame rate (120 / 60 / 30). Defaults to 120 — required for the rev band,
    /// axis/PAP and form release-timing measurements. Changed in Settings only. The camera clamps
    /// this to the highest supported rate ≤ the chosen value. Uploads are kept small by trimming the
    /// clip on-device (VideoTrimmer), NOT by lowering fps.
    @Published var preferredFPS: Int { didSet { defaults.set(preferredFPS, forKey: Keys.preferredFPS) } }

    /// The bowler's profile photo (served by GET /me/avatar; nil when none set). Shown in the tab header
    /// and on Profile. Refreshed on load and after an upload/remove.
    @Published var avatarImage: UIImage?

    // Auth session (tokens live in the Keychain, not here/UserDefaults).
    @Published private(set) var session: AuthSession?
    @Published private(set) var profileComplete: Bool { didSet { defaults.set(profileComplete, forKey: Keys.profileComplete) } }
    private var refreshTask: Task<String?, Never>?

    /// The single source of truth the app root switches on.
    var gate: AuthGate {
        if useDevUser { return .ready }          // dev path bypasses the auth/profile gate (simulator only)
        guard session != nil else { return .unauthenticated }
        return profileComplete ? .ready : .needsProfile
    }

    var isAuthenticated: Bool { session != nil }

    // Capture / session options
    @Published var captureMode: String = "shot"   // "shot" | "form"
    @Published var arrowsBoardText: String = ""
    @Published var breakpointBoardText: String = ""
    @Published var feetBoardText: String = ""
    @Published var laneText: String = ""
    @Published var selectedOilPatternName: String?
    @Published var selectedOilPatternId: String?
    /// Legacy on-device "current ball" name from the pre-arsenal build. Kept only as a display mirror and
    /// the one-time migration source; the arsenal API is the source of truth after `syncArsenal()`.
    @Published var currentBallName: String?
    @Published var shotCount: Int = 0

    // Arsenal (server-backed). `arsenal` is the source of truth after an authed load; `currentBall` is
    // the one row with is_current == true (server-enforced single current ball).
    @Published private(set) var arsenal: [ArsenalBall] = []
    var currentBall: ArsenalBall? { arsenal.first { $0.is_current == true } }

    /// The session's carry-forward target. Seeded from Setup, held across shots, edited by the capture
    /// chip, and updated by "Apply this move". Every live shot sends this as its `intent` (the boards
    /// ACTUALLY used, including any chip edits made after applying a move).
    @Published var sessionTarget = ShotIntent()

    /// The last "Apply this move" proposal snapshot (feet/arrows/breakpoint from the server's
    /// `suggested_target`). Sent as `suggested` on each shot so the server records what was proposed even
    /// if the bowler then edits a board on the chip. Kept until the next Apply; nil when no move applies.
    @Published var sessionSuggested: ShotIntent?

    // End-of-session summary (POST /sessions/{id}/end)
    @Published var endSummary: EndSessionResponse?

    // Pipeline + result
    @Published var pipeline: PipelineState = .idle
    @Published var result: ShotResult?
    @Published var showResult = false

    // Connection check
    @Published var healthText: String?
    @Published var healthIsError = false

    private(set) var sessionId: String?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let baseURL = "ls.apiBaseURL"
        static let devUser = "ls.devUser"
        static let useDevUser = "ls.useDevUser"
        static let handed = "ls.handed"
        static let profileComplete = "ls.profileComplete"
        static let speedUnit = "ls.speedUnit"
        static let speak = "ls.speakAdjustments"
        static let preferredFPS = "ls.preferredFPS"
        static let arsenalMigrated = "ls.arsenalMigrated"
    }

    init() {
        // Cloud Run HTTPS backend (no Mac dependency). Override in the Dev Panel.
        let cloudDefault = "https://lanesight-api-665597641318.us-east1.run.app"
        let savedURL = defaults.string(forKey: Keys.baseURL)
        // Migrate installs still pinned to the old on-Mac dev URL (tailnet / :8787 / plain HTTP — ATS now blocks it).
        if let savedURL, savedURL.contains("ts.net") || savedURL.contains(":8787") || savedURL.hasPrefix("http://") {
            apiBaseURL = cloudDefault
            defaults.set(cloudDefault, forKey: Keys.baseURL)
        } else {
            apiBaseURL = savedURL ?? cloudDefault
        }
        devUser = defaults.string(forKey: Keys.devUser) ?? "dev-shayne"
        useDevUser = defaults.bool(forKey: Keys.useDevUser)
        handed = defaults.string(forKey: Keys.handed) ?? "R"
        profileComplete = defaults.bool(forKey: Keys.profileComplete)
        speedUnit = defaults.string(forKey: Keys.speedUnit) ?? "mph"
        speakAdjustments = defaults.bool(forKey: Keys.speak)
        preferredFPS = (defaults.object(forKey: Keys.preferredFPS) as? Int) ?? 120

        // Restore a persisted Keychain session (tokens survive relaunch; cleared on sign out).
        if let access = Keychain.get(Keychain.Account.accessToken) {
            session = AuthSession(access_token: access,
                                  refresh_token: Keychain.get(Keychain.Account.refreshToken),
                                  expires_in: nil,
                                  user_id: Keychain.get(Keychain.Account.userId))
        }
    }

    // MARK: client construction

    /// Builds an authed APIClient. Injects the real Bearer token (normal path) or `X-Dev-User` only when
    /// the Dev-panel toggle is on. Wires the 401 → refresh → retry handler.
    func makeClient() throws -> APIClient {
        let refresher: @Sendable () async -> String? = { [weak self] in
            await self?.refreshAccessToken()
        }
        return try APIClient(baseURLString: apiBaseURL,
                             accessToken: useDevUser ? nil : session?.access_token,
                             devUser: useDevUser ? devUser : nil,
                             refresher: refresher)
    }

    private func authClient() throws -> AuthClient { try AuthClient(baseURLString: apiBaseURL) }

    /// Reload the profile photo (GET /me/avatar) into `avatarImage`. No-ops quietly if the client can't be
    /// built or the request fails; clears the image on a 404 / empty response.
    func refreshAvatar() async {
        guard let client = try? makeClient() else { avatarImage = nil; return }
        do {
            if let data = try await client.avatarData(), let img = UIImage(data: data) {
                avatarImage = img
            } else {
                avatarImage = nil
            }
        } catch {
            // leave the current image in place on a transient error
        }
    }

    // MARK: auth

    /// Create a real account (email/password) via the Mac API, store tokens in the Keychain, then fetch
    /// the profile to decide whether to route to profile setup or straight to Home.
    func signUp(email: String, password: String) async throws {
        let s = try await authClient().signup(email: email, password: password)
        applySession(s)
        await refreshProfileState()
    }

    /// Sign in with email/password; store tokens in the Keychain and route by profile completeness.
    func signIn(email: String, password: String) async throws {
        let s = try await authClient().signin(email: email, password: password)
        applySession(s)
        await refreshProfileState()
    }

    /// Sign out: clear the Keychain tokens and local session → the app returns to Welcome.
    func signOut() {
        session = nil
        profileComplete = false
        sessionId = nil
        shotCount = 0
        endSummary = nil
        result = nil
        arsenal = []
        sessionTarget = ShotIntent()
        sessionSuggested = nil
        Keychain.delete(Keychain.Account.accessToken)
        Keychain.delete(Keychain.Account.refreshToken)
        Keychain.delete(Keychain.Account.userId)
    }

    /// "Remember me" (Sign in): when false, keep the session only in memory — no Keychain write — so the
    /// app forgets it on next launch. Defaults to true (stay signed in).
    var persistSession = true

    private func applySession(_ s: AuthSession) {
        session = s
        guard persistSession else { return }
        Keychain.set(s.access_token, account: Keychain.Account.accessToken)
        if let rt = s.refresh_token { Keychain.set(rt, account: Keychain.Account.refreshToken) }
        if let uid = s.user_id { Keychain.set(uid, account: Keychain.Account.userId) }
    }

    /// Refreshes the access token once, coalescing concurrent 401s into a single refresh. Returns the new
    /// token, or nil after signing out (refresh token missing/expired).
    func refreshAccessToken() async -> String? {
        if let task = refreshTask { return await task.value }
        guard let rt = session?.refresh_token else { signOut(); return nil }
        let task = Task { [weak self] () -> String? in
            guard let self else { return nil }
            do {
                let s = try await self.authClient().refresh(refreshToken: rt)
                self.applySession(s)
                return s.access_token
            } catch {
                self.signOut()
                return nil
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    /// Fetch the profile and PROMOTE to complete when the required gate (a saved date of birth) is set.
    /// Promote-only on purpose: a read miss / fetch error must not bounce an already-set-up user back
    /// through setup. `signOut()` resets the flag, so each fresh sign-in re-derives it honestly.
    func refreshProfileState() async {
        guard let client = try? makeClient() else { return }
        if let p = try? await client.getProfile() {
            if p.dob?.isEmpty == false { profileComplete = true }
            if let h = p.handedness { handed = (h == "left") ? "L" : "R" }
        }
    }

    // MARK: arsenal

    /// Fetches the arsenal and makes the server the source of truth. On the FIRST authed launch, migrates
    /// any locally-stored ball (the pre-arsenal `currentBallName`) to /me/arsenal as the current ball,
    /// then persists a flag so migration runs exactly once. After this, read/write only through the API.
    func syncArsenal() async {
        guard let client = try? makeClient() else { return }
        if !defaults.bool(forKey: Keys.arsenalMigrated) {
            if let legacy = currentBallName?.trimmingCharacters(in: .whitespaces), !legacy.isEmpty {
                // Map the local name → `name`; mark it current. Weight/layout/surface weren't stored locally.
                _ = try? await client.addBall(name: legacy, makeCurrent: true)
            }
            defaults.set(true, forKey: Keys.arsenalMigrated)
        }
        if let balls = try? await client.getArsenal() {
            arsenal = balls
            currentBallName = currentBall?.displayName        // keep the legacy display mirror in sync
        }
    }

    /// Adds a ball (catalog via `ballModelId`, or custom via `name`) and re-syncs the arsenal.
    func addBall(ballModelId: String? = nil, name: String? = nil, nickname: String? = nil,
                 weightLb: Double? = nil, colorDesc: String? = nil, layoutSystem: String? = nil,
                 layout: String? = nil, surface: String? = nil, makeCurrent: Bool = false) async throws {
        let client = try makeClient()
        _ = try await client.addBall(ballModelId: ballModelId, name: name, nickname: nickname,
                                     weightLb: weightLb, colorDesc: colorDesc, layoutSystem: layoutSystem,
                                     layout: layout, surface: surface, makeCurrent: makeCurrent)
        await syncArsenal()
    }

    /// Makes `id` the one current ball (PATCH is_current) and re-syncs.
    func setCurrentBall(id: String) async throws {
        let client = try makeClient()
        try await client.setCurrentBall(id: id)
        await syncArsenal()
    }

    /// Patches an arsenal row (layout/surface/weight/nickname/retired/…) and re-syncs.
    func updateBall(id: String, patch: [String: Any]) async throws {
        let client = try makeClient()
        try await client.updateBall(id: id, patch: patch)
        await syncArsenal()
    }

    /// Applies a server-computed next-shot target to the carry-forward target. Only the non-null boards
    /// are applied; a null board leaves the current value unchanged. No board math is done in Swift.
    func applySuggestedTarget(_ t: SuggestedTarget) {
        if let f = t.feet_board { sessionTarget.feetBoard = f }
        if let a = t.arrows_board { sessionTarget.arrowsBoard = a }
        if let b = t.breakpoint_board { sessionTarget.breakpointBoard = b }
        // Snapshot the proposal (including the geometrically-derived breakpoint). This is the record of
        // what was proposed; a later chip edit changes `sessionTarget` (used) but leaves this untouched.
        sessionSuggested = ShotIntent(feetBoard: t.feet_board, arrowsBoard: t.arrows_board,
                                      breakpointBoard: t.breakpoint_board)
    }

    /// Reports the user's leave for a shot whose pins weren't read (NextShotStates "PINS NOT READ"),
    /// then merges the server's recomputed insights back onto the current result so the Next Shot card
    /// re-renders from the new `state`. Keeps the existing metrics/score/isUpload flags.
    func reportPins(shotId: String, leave: String?, pins: [Int]?, strike: Bool) async throws {
        let client = try makeClient()
        let resp = try await client.reportPins(shotId: shotId, leave: leave, pins: pins, strike: strike)
        guard let record = resp.record, var r = result, r.shotId == shotId else { return }
        let insights = record.insights
        let moveRec = insights?.recommendations?.first { $0.direction != nil && $0.move_feet != nil }
            ?? insights?.recommendations?.first { $0.reason?.isEmpty == false }
        r.metrics = MetricDisplay.ordered(record.metrics ?? [:])
        r.suggestedTarget = insights?.suggested_target
        r.recommendation = moveRec
        r.insightsState = insights?.state
        r.insightsConfidence = insights?.confidence
        r.insightsNote = insights?.note
        result = r
    }

    /// True when a board's current (used) value still matches the last applied suggestion — i.e. it came
    /// from "Apply this move" and the bowler hasn't edited it. Drives the "suggested" tag on the chip.
    var breakpointIsSuggested: Bool {
        guard let s = sessionSuggested, let b = s.breakpointBoard else { return false }
        return sessionTarget.breakpointBoard == b
    }

    // MARK: connection check

    func checkConnection() async {
        healthText = nil
        healthIsError = false
        do {
            let client = try makeClient()
            let health = try await client.health()
            let mode = health.config?.mode ?? "?"
            let v = health.versions ?? [:]
            let versions = ["api", "core", "formula", "rules", "app_compat"]
                .compactMap { k in v[k].map { "\(k) \($0)" } }
                .joined(separator: " · ")
            healthText = "status \(health.status ?? "?") · mode \(mode)\n\(versions)"
            healthIsError = false
        } catch {
            healthText = error.localizedDescription
            healthIsError = true
        }
    }

    // MARK: full shot pipeline

    func processShot(fileURL: URL) async { await runPipeline(fileURL: fileURL, source: "live") }

    /// Analyze a clip picked from Photos/Files (POST /uploads) through the same job pipeline + Shot card.
    func processUpload(fileURL: URL) async { await runPipeline(fileURL: fileURL, source: "upload") }

    private func runPipeline(fileURL: URL, source: String) async {
        do {
            let client = try makeClient()
            // Snapshot the capture mode for THIS shot up front so detection later can't be confused by a
            // mode change while the clip is analyzing. This is also exactly what's sent as `capture_mode`.
            let capturedMode = captureMode

            // 1. Ensure a session exists for this app run — LIVE captures only. An upload (DEC-055) is a
            // STANDALONE analysis: it never creates or joins a session (so it stays out of Recent
            // sessions / activity and never feeds Stats, the Score, tiers or achievements).
            let sid: String?
            if source == "live" {
                if let existing = sessionId {
                    sid = existing
                } else {
                    pipeline = .creatingSession
                    let created = try await client.createSession(mode: "practice").id
                    sessionId = created
                    sid = created
                }
            } else {
                sid = nil
            }

            // 2. Trim the clip to the shot window ON-DEVICE and fit it under the upload size cap. Both live
            // captures and Photos uploads go through this: the window trim is lossless (original fps +
            // resolution preserved, dead time at head/tail cut); only a clip still over the cap is re-encoded
            // to fit (bitrate only). This keeps uploads under Supabase's ~50 MB free-tier limit; the server
            // re-trims precisely afterwards.
            pipeline = .trimming
            let uploadURL = await VideoTrimmer.trimForUpload(fileURL)

            // 3. Upload the clip (multipart) with progress.
            pipeline = .uploading(0)
            // Live shots carry the session's current target (carry-forward / chip / Apply-this-move).
            // Uploads seed that target from the Upload screen's fields so the Shot card shows it too.
            if source != "live" {
                sessionTarget = ShotIntent(
                    feetBoard: Double(feetBoardText.trimmingCharacters(in: .whitespaces)),
                    arrowsBoard: Double(arrowsBoardText.trimmingCharacters(in: .whitespaces)),
                    breakpointBoard: Double(breakpointBoardText.trimmingCharacters(in: .whitespaces)))
                sessionSuggested = nil      // uploads have no Apply-this-move proposal
            }
            let ball = currentBall
            let metadata = ShotMetadata(
                handed: handed,
                captureMode: capturedMode,
                source: source,
                intent: sessionTarget,
                suggested: sessionSuggested,
                ballConfigurationId: ball?.ball_configuration_id,
                userBallId: ball?.id
            )
            // Upload the clip straight to Supabase Storage (no API request-size cap), then analyze from there.
            let target = try await client.signedUploadURL()
            try await client.putClipToStorage(uploadURL: target.upload_url, fileURL: uploadURL) { [weak self] frac in
                self?.pipeline = .uploading(frac)
            }

            // 4. Analyze. The Phase-1 backend runs the CV INLINE, so this one request blocks for the whole
            //    analysis — we show the processing state for its full duration (treated as async in the UI;
            //    the result is durable in Supabase). `sessionId` nil → standalone upload; set → live shot.
            pipeline = .analyzing(state: "running", timings: [:])
            let created = try await client.analyzeFromStorage(
                storagePath: target.path,
                sessionId: (source == "upload" ? nil : sid),
                metadata: metadata)

            // Synchronous backend ⇒ the job is already terminal; one fetch gets its state + timings footer.
            let last = try await client.job(created.job_id)
            if last.state == "failed" {
                pipeline = .failed("Analysis failed: \(last.reason ?? "unknown reason")")
                return
            }
            pipeline = .analyzing(state: last.state, timings: last.timings ?? [:])

            // 5. Fetch the shot record + score; carry the analyze-job footer onto the card.
            pipeline = .fetching
            let shot = try await client.shot(created.shot_id)
            let score = try await client.score()
            let record = shot.record

            // Detect a form result: the mode this shot was captured in wins; otherwise fall back to the
            // record carrying `form_version` or FORM_P1 keys. This never misroutes a ball shot — a ball
            // record has neither form_version nor the FORM_P1 keys.
            let isForm = capturedMode == "form"
                || record?.form_version != nil
                || FormMetricDisplay.looksLikeForm(record?.metrics)

            // Order metrics with the right grouping for the kind of result.
            let rawMetrics = record?.metrics ?? [:]
            let metrics = isForm ? FormMetricDisplay.ordered(rawMetrics) : MetricDisplay.ordered(rawMetrics)

            let insights = record?.insights
            // The actionable move rec (reason/direction for the "Apply this move" label): first rec that
            // names a direction + move distance; otherwise the first rec with a reason. Ball-only.
            let moveRec = insights?.recommendations?.first { $0.direction != nil && $0.move_feet != nil }
                ?? insights?.recommendations?.first { $0.reason?.isEmpty == false }
            var built = ShotResult(shotId: created.shot_id, metrics: metrics, score: score,
                                   footer: isForm ? nil : last.result,
                                   suggestedTarget: isForm ? nil : insights?.suggested_target,
                                   recommendation: isForm ? nil : moveRec,
                                   insightsState: isForm ? nil : insights?.state,
                                   insightsConfidence: isForm ? nil : insights?.confidence,
                                   insightsNote: isForm ? nil : insights?.note,
                                   captureFarLaneLimited: record?.capture_quality?.far_lane == "limited",
                                   captureReason: record?.capture_quality?.reason,
                                   isUpload: false,
                                   isForm: isForm,
                                   formView: record?.view,
                                   formStatus: record?.status,
                                   formVersion: record?.form_version)
            if isForm { Self.attachFormFundamentals(&built, record) }
            result = built
            shotCount += 1
            pipeline = .done
            showResult = true

            // Clean up the temp clips (the original recording and, if different, the trimmed upload).
            try? FileManager.default.removeItem(at: fileURL)
            if uploadURL != fileURL { try? FileManager.default.removeItem(at: uploadURL) }
        } catch {
            pipeline = .failed(error.localizedDescription)
        }
    }

    /// Builds a `ShotResult` for a previously analyzed shot (Lab › Uploads row → shot card). Fetches the
    /// stored record + the current score. There is no analyze-job footer for a past result, so score
    /// deltas / nudges are absent by design. Sets `result` and returns true on success; the caller drives
    /// its own presentation (kept off `showResult` so it never collides with the live pipeline's sheet).
    @discardableResult
    func loadShotResult(shotId: String, captureModeHint: String?) async -> Bool {
        do {
            let client = try makeClient()
            let shot = try await client.shot(shotId)
            let score = try await client.score()
            let record = shot.record
            let isForm = captureModeHint == "form"
                || record?.form_version != nil
                || FormMetricDisplay.looksLikeForm(record?.metrics)
            let rawMetrics = record?.metrics ?? [:]
            let metrics = isForm ? FormMetricDisplay.ordered(rawMetrics) : MetricDisplay.ordered(rawMetrics)
            let insights = record?.insights
            let moveRec = insights?.recommendations?.first { $0.direction != nil && $0.move_feet != nil }
                ?? insights?.recommendations?.first { $0.reason?.isEmpty == false }
            var built = ShotResult(shotId: shotId, metrics: metrics, score: score,
                                   footer: nil,
                                   suggestedTarget: isForm ? nil : insights?.suggested_target,
                                   recommendation: isForm ? nil : moveRec,
                                   insightsState: isForm ? nil : insights?.state,
                                   insightsConfidence: isForm ? nil : insights?.confidence,
                                   insightsNote: isForm ? nil : insights?.note,
                                   captureFarLaneLimited: record?.capture_quality?.far_lane == "limited",
                                   captureReason: record?.capture_quality?.reason,
                                   // Prefer the shot row's top-level source (reliable); fall back to the
                                   // record's. An upload unless either says it was a live shot.
                                   isUpload: (shot.source ?? record?.source) != "live",
                                   isForm: isForm,
                                   formView: record?.view,
                                   formStatus: record?.status,
                                   formVersion: record?.form_version)
            built.shotNumber = shot.sequence
            if isForm { Self.attachFormFundamentals(&built, record) }
            result = built
            return true
        } catch {
            return false
        }
    }

    /// Copies the form fundamentals v1 payload (DEC-057) from the shot record onto the result. Everything
    /// stays absent when the record didn't carry it — nothing is fabricated.
    private static func attachFormFundamentals(_ r: inout ShotResult, _ record: ShotRecord?) {
        guard let record else { return }
        r.formFPS = record.fps
        r.keyFrames = record.key_frames ?? []
        r.events = (record.events ?? [:]).compactMapValues { $0.value }
        r.timingCheckpoints = record.timing_checkpoints ?? [:]
        r.measuredPositions = record.measured_positions ?? [:]
        r.swingTiming = record.swing_timing
        r.coachingCues = record.coaching_cues
        r.formFocus = record.focus
        r.formFooter = record.footer
    }

    // MARK: notifications / celebrations
    //
    // Surface at most one pending notification at a quiet moment (never during recording). The server
    // sorts undelivered notifications by priority (tier > achievement), so the first is the one to show;
    // the rest stay undelivered and get batched into the Summary.

    func fetchTopPendingNotification() async -> AppNotification? {
        guard let client = try? makeClient() else { return nil }
        let list = (try? await client.notifications(undelivered: true)) ?? []
        guard let top = list.first else { return nil }
        try? await client.markNotificationDelivered(top.id)
        return top
    }

    func markNotificationDelivered(_ id: String) async {
        guard let client = try? makeClient() else { return }
        try? await client.markNotificationDelivered(id)
    }

    func dismissNotification(_ id: String) async {
        guard let client = try? makeClient() else { return }
        try? await client.dismissNotification(id)
    }

    /// Permanently delete the account (DELETE /me), then sign out locally (clears the Keychain session).
    func deleteAccount() async throws {
        let client = try makeClient()
        try await client.deleteAccount()
        signOut()
    }

    func submitFeedback(rating: Int, text: String) async throws {
        guard let sid = sessionId else { return }
        let client = try makeClient()
        try await client.feedback(sessionId: sid, rating: rating, text: text)
    }

    func resetPipeline() {
        pipeline = .idle
        showResult = false
    }

    var activeSessionId: String? { sessionId }

    /// Starts a new live session from the Setup screen (mode, lane, oil pattern) and resets counters.
    func startLiveSession(mode: String, lane: String?, oilPatternId: String?) async throws {
        let client = try makeClient()
        let session = try await client.createSessionFull(mode: "practice", lanePair: lane, oilPatternId: oilPatternId)
        sessionId = session.id
        shotCount = 0
        endSummary = nil
        captureMode = mode
        // Seed the carry-forward target from the Setup fields (optional). It then carries shot-to-shot
        // and is edited only via the capture chip or "Apply this move" — no need to reopen Setup.
        sessionTarget = ShotIntent(
            feetBoard: Double(feetBoardText.trimmingCharacters(in: .whitespaces)),
            arrowsBoard: Double(arrowsBoardText.trimmingCharacters(in: .whitespaces)),
            breakpointBoard: Double(breakpointBoardText.trimmingCharacters(in: .whitespaces)))
        sessionSuggested = nil      // fresh session: no applied move yet
    }

    /// Records the sensor answer for the shot shown on the shot card (PATCH /shots/{id}).
    func answerSensor(shotId: String, used: Bool, sensorId: String?) async throws {
        let client = try makeClient()
        try await client.patchShotSensor(shotId: shotId, sensorUsed: used, sensorId: sensorId)
    }

    /// Full session feedback (rating + tags + diagnostics), used by the feedback sheet.
    func submitSessionFeedback(rating: Int, tags: [String], text: String, diagnostics: Bool) async throws {
        guard let sid = sessionId else { return }
        let client = try makeClient()
        try await client.feedbackFull(sessionId: sid, rating: rating, tags: tags,
                                      text: text.isEmpty ? nil : text, diagnostics: diagnostics)
    }

    /// Ends the active session; stores the returned summary for the summary screen.
    func endCurrentSession() async throws {
        guard let sid = sessionId else { return }
        let client = try makeClient()
        endSummary = try await client.endSession(sid)
        sessionId = nil
    }

    /// Marks the bowler profile complete after the setup + add-ball steps → the app root switches to Home.
    func finishProfileSetup() {
        profileComplete = true
    }
}
