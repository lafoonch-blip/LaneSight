import Foundation
import SwiftUI
import Combine
import UIKit
import Photos

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
    // DEC-088/090 shot card: fitted lane path + pinned points, Power, baseline, and the two-part coach read.
    var pathFit: PathFit?
    var keyPoints: [String: ShotKeyPoint] = [:]
    var baseline: Baseline?
    var impactEnergyJ: Double?
    var coachThrow: CoachThrow?
    var coachLane: CoachLane?
    var coachAction: CoachAction?
    // DEC-097: the ball this shot was thrown with (shown on the card). Live shots set it from the current ball;
    // a loaded shot from its stored per-shot ball.
    var ballName: String? = nil
    // Capture-quality banner (B): shown above "Target vs actual" when the far lane was limited.
    var captureFarLaneLimited: Bool = false
    var captureReason: String?
    /// DEC-122: per-stage analysis outcome (ok/failed/skipped). Populated for every result; shown only on
    /// dev/TestFlight builds as the "What worked" list. Empty when the server didn't send a stage report.
    var stageReport: [String: StageOutcome] = [:]
    /// DEC-126: which engine produced the DISPLAYED measurement — "server" (default) or "iphone" (on-device
    /// primary). The server-only metrics (boards/entry/loft) + Score/coaching are always server-authoritative.
    var engine: String = "server"
    /// DEC-127 Offline Analysis state: the on-device metrics are shown but coaching needs connectivity — the
    /// coaching section is ABSENT (never a half-populated placeholder), replaced by one line. The queued metrics
    /// call enriches the saved shot in history when it lands.
    var coachingPendingOffline: Bool = false
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
    /// Display-only pose-skeleton overlay joints per key frame (visibility-gated, crop-normalized). Each
    /// value is 33 joints, [x,y] in the cropped still or nil for a joint the pose wasn't confident about.
    var keyFramePoses: [String: [[Double]?]] = [:]
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
    /// DEC-099: also keep a copy of every live recording in the phone's Photos library. OFF by default.
    /// This is the ONLY video-storage choice the bowler makes; how long video stays on LaneSight's servers
    /// is set by LaneSight (plan-based), not by the user.
    @Published var saveVideosToPhone: Bool { didSet { defaults.set(saveVideosToPhone, forKey: Keys.saveVideosToPhone) } }

    /// The bowler's profile photo (served by GET /me/avatar; nil when none set). Shown in the tab header
    /// and on Profile. Refreshed on load and after an upload/remove.
    @Published var avatarImage: UIImage?
    /// True once Home has finished its first data load — drives the branded launch splash (seamless startup).
    @Published var homeLoaded = false

    // Auth session (tokens live in the Keychain, not here/UserDefaults).
    @Published private(set) var session: AuthSession?
    @Published private(set) var profileComplete: Bool { didSet { defaults.set(profileComplete, forKey: Keys.profileComplete) } }
    /// Whether the one-time "how it works" intro has been shown (first-run demo before Home).
    @Published private(set) var hasSeenIntro: Bool { didSet { defaults.set(hasSeenIntro, forKey: Keys.seenIntro) } }
    func markIntroSeen() { hasSeenIntro = true }
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
    /// DEC-099: the bowler's default ball (what a NEW session starts with). Nil until they set one.
    var defaultBall: ArsenalBall? { arsenal.first { $0.is_default == true && $0.retired != true } }

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
    // DEC-086: an upload analysis takes over a full-screen cover presented at the APP ROOT (not on the
    // Upload screen), so the result can never be orphaned if the user navigates away mid-analysis.
    @Published var uploadBusy = false

    // DEC-096: in a LIVE session the record→analyze→result flow is presented as a full-screen cover OVER the
    // Active Session (SessionView / FormSessionView). This flag is that cover's presentation binding, so any
    // exit deep inside it (result Done, failure "Back to session", capture Done) returns to the Active Session
    // by setting it false — never back to Session Setup.
    @Published var inLiveCapture = false
    // The last analyzed clip + its source, so a failed analysis can Retry without re-recording (DEC-096/086).
    private(set) var lastCaptureURL: URL?
    private var lastSource = "live"

    // An analysis that finished (or failed) while the app was CLOSED. Surfaced non-intrusively on Home as a
    // "Shot analyzed while you were away · View" banner — NOT a result sheet at launch (2026-10-30). Tapping
    // opens the result; a failed one shows the friendly reason + Retry.
    struct AwayResult: Equatable { let shotId: String; let mode: String?; let failed: Bool; let sessionId: String? }
    @Published var awayResult: AwayResult?

    // Recover-on-resume: the analysis runs server-side and its result is durable in Supabase even if the app
    // is backgrounded and the request drops. We persist a marker for the in-flight analysis so that on return
    // to the foreground we can fetch the finished shot and show it, instead of leaving a stale failure.
    private struct PendingAnalysis: Codable { let source: String; let sessionId: String?; let startedAt: Double }
    private var pendingAnalysis: PendingAnalysis? {
        get { defaults.data(forKey: "ls.pendingAnalysis").flatMap { try? JSONDecoder().decode(PendingAnalysis.self, from: $0) } }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: "ls.pendingAnalysis") }
            else { defaults.removeObject(forKey: "ls.pendingAnalysis") }
        }
    }

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
        static let seenIntro = "ls.hasSeenIntro"
        static let saveVideosToPhone = "ls.saveVideosToPhone"
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
        hasSeenIntro = defaults.bool(forKey: Keys.seenIntro)
        speedUnit = defaults.string(forKey: Keys.speedUnit) ?? "mph"
        speakAdjustments = defaults.bool(forKey: Keys.speak)
        preferredFPS = (defaults.object(forKey: Keys.preferredFPS) as? Int) ?? 120
        saveVideosToPhone = defaults.bool(forKey: Keys.saveVideosToPhone)

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

    // MARK: §2 product analytics (DEC-098 M3)
    // Consent-aware, masked product events. The server pseudonymises (user_ref) and dedups on
    // client_event_id, so a resend after an offline gap never double-counts. Fire-and-forget — analytics
    // must never block or fail a user action. Emit sites (call model.track(...)):
    //   • "app_opened"         — once per launch (trackAppOpenedOnce, from the app root's launch task)
    //   • "session_started"    — when a practice/live session is created (startLiveSession + lazy live create)
    //   • "first_shot_analyzed"— on the first successful live shot result in a session (runPipeline)
    private var eventQueue: [[String: Any]] = []

    func track(_ name: String, props: [String: Any]? = nil, feature: String? = nil, flowStep: String? = nil) {
        var e: [String: Any] = ["event_name": name,
                                "client_event_id": UUID().uuidString,
                                "occurred_at": ISO8601DateFormatter().string(from: Date())]
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { e["app_version"] = v }
        if let feature { e["feature"] = feature }
        if let flowStep { e["flow_step"] = flowStep }
        if let props { e["props"] = props }
        eventQueue.append(e)
        flushEvents()
    }

    private func flushEvents() {
        guard !eventQueue.isEmpty, let client = try? makeClient() else { return }
        let batch = eventQueue
        eventQueue = []
        Task { await client.postEvents(batch) }   // idempotent server-side; dropped on failure, resent next track
    }

    /// Fire "app_opened" once per process launch — not on every foreground resume (scenePhase .active can
    /// fire many times a session). Called from the app root's launch task.
    private var didTrackAppOpen = false
    func trackAppOpenedOnce() {
        guard !didTrackAppOpen else { return }
        didTrackAppOpen = true
        track("app_opened")
        flushMetricsQueue()   // DEC-127: send any coaching calls that were queued offline, so history enriches
    }

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
        homeLoaded = false          // re-show the launch splash on the next sign-in
        avatarImage = nil
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
                 layout: String? = nil, surface: String? = nil, makeCurrent: Bool = false,
                 makeDefault: Bool = false) async throws {
        let client = try makeClient()
        _ = try await client.addBall(ballModelId: ballModelId, name: name, nickname: nickname,
                                     weightLb: weightLb, colorDesc: colorDesc, layoutSystem: layoutSystem,
                                     layout: layout, surface: surface, makeCurrent: makeCurrent,
                                     makeDefault: makeDefault)
        await syncArsenal()
    }

    /// DEC-099: make `id` the bowler's one default ball (`isDefault: false` clears it) and re-sync.
    func setDefaultBall(id: String, isDefault: Bool = true) async throws {
        let client = try makeClient()
        try await client.updateBall(id: id, patch: ["is_default": isDefault])
        await syncArsenal()
    }

    /// DEC-099: a NEW session starts with the default ball. Called when Setup opens for a fresh session;
    /// no-op when there's no default or it's already the current ball. "From your last session" still
    /// overrides it afterwards.
    func applyDefaultBallForNewSession() async {
        guard let d = defaultBall, currentBall?.id != d.id else { return }
        try? await setCurrentBall(id: d.id)
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

    func processShot(fileURL: URL) async {
        lastCaptureURL = fileURL; lastSource = "live"
        // DEC-099: save the ORIGINAL recording to Photos first (before trimming/cleanup), so the bowler keeps
        // the clip even if the analysis fails. Never blocks the analysis on a Photos error.
        if saveVideosToPhone { _ = await Self.saveVideoToPhotos(fileURL) }
        await runPipeline(fileURL: fileURL, source: "live")
    }

    /// Asks for add-only Photos access (no read access to the library). Returns true when granted.
    static func requestPhotosAddAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    /// Adds the video at `url` to the Photos library. Returns false (quietly) if access is missing or the
    /// save fails — the recording still goes to analysis either way.
    static func saveVideoToPhotos(_ url: URL) async -> Bool {
        guard await requestPhotosAddAccess() else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges(photosAddVideo(url))
            return true
        } catch {
            return false
        }
    }

    /// Built in a nonisolated context so the change block is NOT main-actor isolated: Photos runs it on its
    /// own background queue (a main-actor-inferred closure would trip the executor check there).
    nonisolated private static func photosAddVideo(_ url: URL) -> @Sendable () -> Void {
        { _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
    }

    /// Analyze a clip picked from Photos/Files (POST /uploads) through the same job pipeline + Shot card.
    /// Raises the root-level blocking cover (DEC-086) for the whole analysis so it's never orphaned.
    func processUpload(fileURL: URL) async {
        lastCaptureURL = fileURL; lastSource = "upload"
        pipeline = .trimming
        uploadBusy = true
        await runPipeline(fileURL: fileURL, source: "upload")
    }

    /// DEC-096: re-analyze the last clip after a failure — no re-recording. Stays in whichever cover is up
    /// (the live capture cover or the root upload cover).
    func retryLastAnalysis() async {
        guard let url = lastCaptureURL else { return }
        if lastSource == "upload" { uploadBusy = true }
        await runPipeline(fileURL: url, source: lastSource)
    }

    /// DEC-096: collapse the live capture/analyze/result cover back to the Active Session.
    func exitToSession() { inLiveCapture = false; resetPipeline() }

    /// DEC-106: fire-and-forget native on-device shadow analysis of the just-analysed clip. Copies the clip
    /// (the upload temp is deleted when the pipeline finishes), runs the engine OFF the main actor, then POSTs
    /// the result as platform='ios'. Ball shots only; every failure is swallowed — it must never affect the
    /// user's result, Score or UI.
    /// DEC-106: the on-device shadow is non-production — it runs ONLY behind an owner/dev flag, never for real
    /// users on the production branch. Default: on for DEBUG (owner dev builds), off for Release; overridable via
    /// the `ls.ondevice_shadow` UserDefaults key.
    static var shadowEnabled: Bool {
        if let v = UserDefaults.standard.object(forKey: "ls.ondevice_shadow") as? Bool { return v }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// DEC-122: show per-analysis diagnostics (the "What worked" stage list) on DEV and TESTFLIGHT builds, never
    /// for App Store users. TestFlight is detected by the sandbox receipt. Overridable via `ls.diagnostics`.
    static var diagnosticsEnabled: Bool {
        if let v = UserDefaults.standard.object(forKey: "ls.diagnostics") as? Bool { return v }
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// DEC-126: the on-device engine is the PRIMARY measurement for live shots. OFF until the switch ships; flip
    /// per-device / on TestFlight via `ls.ondevice_primary` to validate. When on, a live shot's speed/rev come
    /// from the on-device engine; the server stays the shadow/reference and remains authoritative for Score,
    /// coaching, and the server-only metrics (boards/entry/loft).
    static var onDevicePrimary: Bool {
        if let v = UserDefaults.standard.object(forKey: "ls.ondevice_primary") as? Bool { return v }
        return false
    }
    /// DEC-126 guardrail: a live on-device result slower than this falls back to the server. The ONLY blockers are
    /// a crash or > 30 s — no accuracy gate. `nonisolated` so the off-main-actor measurement task can read it.
    nonisolated static let ondevicePrimaryMaxLatencyS: Double = 30.0

    /// The in-flight shadow, if any. Single-flight: a new shot cancels the previous shadow so the on-device
    /// engine can never pile up across shots (battery / thermal / next-shot contention — P0 2026-10-29).
    private var shadowTask: Task<Void, Never>?

    private func launchShadow(clipURL: URL, shotId: String, source: String, sessionId: String?) {
        guard Self.shadowEnabled else { return }               // owner/dev only — off for real users (DEC-106)
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-\(shotId).mov")
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: clipURL, to: copy)) != nil else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let mode = captureMode
        let hand = handed
        let capSeconds: UInt64 = 60       // hard wall-clock cap; the engine is aborted past this (P0 2026-10-29)
        shadowTask?.cancel()                                   // single-flight: drop any prior shadow first
        shadowTask = Task.detached(priority: .utility) {
            // Run the shadow on a TIGHT shot window (the same shot the server analyses), not the full recording:
            // the upload clip keeps a 10 s settle tail for the server's own re-trim, which made the shadow chew
            // 512 s. A ~5 s tail covers ball→pins→impact and is far faster (DEC-106 shadow — form keeps its full
            // approach, DEC-101). Minor window-boundary differences are fine for a parity comparison.
            let shadowClip = (mode == "form") ? copy
                : await VideoTrimmer.trimToShotWindow(copy, tail: 5.0)
            defer {
                try? FileManager.default.removeItem(at: copy)
                if shadowClip != copy { try? FileManager.default.removeItem(at: shadowClip) }
            }
            // Race the engine against a hard cap. The 512 s run (2026-10-29) came from processing the full
            // untrimmed clip through several full-res decode passes; until that's trimmed/frame-skipped, the
            // cap stops a slow shadow from burning the battery or blocking the next shot. The engine loops
            // check Task.isCancelled, so cancelAll() actually halts the CPU work. Each child serialises to
            // Data (Sendable) BEFORE crossing the task boundary — [String: Any] never leaves its own task.
            let json: Data? = await withTaskGroup(of: Data?.self) { group in
                group.addTask {
                    let payload: [String: Any] = (mode == "form")
                        ? await OnDeviceFormShadow.run(clipURL: shadowClip, shotId: shotId, source: source,
                                                       sessionId: sessionId, handed: hand, appVersion: appVersion)
                        : await OnDeviceShadow.run(clipURL: shadowClip, shotId: shotId, source: source,
                                                   sessionId: sessionId, captureMode: mode, appVersion: appVersion)
                    return try? JSONSerialization.data(withJSONObject: payload)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: capSeconds * 1_000_000_000)
                    // On timeout, post an honest SHADOW_UNAVAILABLE marker so the slow run stays visible in ops.
                    let marker: [String: Any] = [
                        "shot_id": shotId, "source": source, "capture_mode": mode, "basis": "unavailable",
                        "note": "on-device shadow aborted after \(capSeconds)s cap (too slow on the full clip)",
                        "device_perf": ["latency_s": Double(capSeconds)],
                    ].merging(sessionId.map { ["session_id": $0] } ?? [:]) { a, _ in a }
                    return try? JSONSerialization.data(withJSONObject: marker)
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            if Task.isCancelled { return }                     // superseded by a newer shot — drop silently
            guard let json else { return }
            await MainActor.run { [weak self] in
                guard let self, let client = try? self.makeClient() else { return }
                Task { try? await client.postShadow(json) }        // POST via a fresh client, like the failure hook
            }
        }
    }

    /// DEC-126: the on-device engine's measurement, carried back to the UI as a Sendable value (no [String:Any]
    /// crosses the task boundary). All three speeds are best_effort by policy; nil = the engine couldn't measure it.
    struct OnDeviceMeasurement: Sendable {
        let ballSpeed: Double?
        let foulToPins: Double?
        let revRate: Double?
        let basis: String       // best_effort | unavailable
        let note: String        // honest reason when a value is unavailable
        let latencyS: Double
        // DEC-127: the FULL structured on-device metrics ({name:{value,status,unit,note,...}}) as JSON (Sendable),
        // forwarded to POST /shots/metrics and used to render all metrics in the Offline state. nil = engine failed.
        var detailedJSON: Data? = nil
        // DEC-127: the ball path (trajectory.smoothed/series, board vs ft) as JSON — drives the shot-card lane view
        // (path_fit) online via the server + is rendered locally in the Offline state. nil when no path was fit.
        var trajectoryJSON: Data? = nil
    }

    /// DEC-126: run the on-device engine as the PRIMARY measurement for a live shot. Returns the measurement, or
    /// `nil` to FALL BACK to the server — the ONLY fallback triggers are a crash or > 30 s (no accuracy gate). An
    /// `unavailable`-but-fast result is a valid primary result (honest unavailable + reason), NOT a fallback.
    /// Mirrors the shadow's shot-window trim + hard cap.
    nonisolated private func measureOnDevicePrimary(clipURL: URL, shotId: String, source: String,
                                                    sessionId: String?, mode: String) async -> OnDeviceMeasurement? {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("odp-\(shotId).mov")
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: clipURL, to: copy)) != nil else { return nil }
        let capS = UInt64(Self.ondevicePrimaryMaxLatencyS)
        let result: OnDeviceMeasurement? = await withTaskGroup(of: OnDeviceMeasurement?.self) { group in
            group.addTask {
                let clip = (mode == "form") ? copy : await VideoTrimmer.trimToShotWindow(copy, tail: 5.0)
                defer { if clip != copy { try? FileManager.default.removeItem(at: clip) } }
                let body = await OnDeviceShadow.run(clipURL: clip, shotId: shotId, source: source,
                                                    sessionId: sessionId, captureMode: mode, appVersion: appVersion)
                let perf = body["device_perf"] as? [String: Any] ?? [:]
                let m = body["metrics"] as? [String: Any] ?? [:]
                let detailed = body["metrics_detailed"] as? [String: Any]
                let dj = detailed.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                let traj = body["trajectory"] as? [String: Any]
                let tj = traj.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                return OnDeviceMeasurement(
                    ballSpeed: m["ball_speed"] as? Double, foulToPins: m["speed_avg_foul_to_pins"] as? Double,
                    revRate: m["rev_rate"] as? Double, basis: body["basis"] as? String ?? "unavailable",
                    note: body["note"] as? String ?? "", latencyS: perf["latency_s"] as? Double ?? .infinity,
                    detailedJSON: dj, trajectoryJSON: tj)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: capS * 1_000_000_000)
                return nil      // > 30 s -> fall back to the server
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        try? FileManager.default.removeItem(at: copy)
        guard let result, result.latencyS <= Self.ondevicePrimaryMaxLatencyS else { return nil }
        return result
    }

    // DEC-127 removed `immediateOnDeviceResult` + `applyOnDevicePrimary` (the DEC-126 show-then-fold path): the
    // result now renders ONCE from the metrics-call card (Complete) or the on-device metrics (Offline), never a
    // 3-metric placeholder that's filled in later. See `buildResultFromCard` / `offlineResult`.

    // MARK: - DEC-127 on-device-first result builders

    /// Parse the on-device structured metrics JSON into display Metric cells. Measured → its status (ok);
    /// the engine's explicit unavailable → unavailable + its reason. Never fabricates a value.
    private static func metricDictFromDetailed(_ data: Data?) -> [String: Metric] {
        guard let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: Metric] = [:]
        for (key, v) in obj {
            guard let d = v as? [String: Any] else { continue }
            out[key] = Metric(metric: key, value: d["value"] as? Double, unit: d["unit"] as? String,
                              status: d["status"] as? String ?? "unavailable", note: d["note"] as? String,
                              confidence: nil, uncertainty: d["uncertainty"] as? Double)
        }
        return out
    }

    /// DEC-127 Complete Analysis: build the shown result from the metrics-endpoint response (score + coaching +
    /// the full card). engine = iphone (the measurements are on-device; score/coaching are server-authoritative).
    private static func buildResultFromCard(_ resp: MetricsResultResponse, isUpload: Bool) -> ShotResult {
        let record = resp.shot.record
        let metrics = MetricDisplay.ordered(record?.metrics ?? [:])
        let insights = record?.insights
        let moveRec = insights?.recommendations?.first { $0.direction != nil && $0.move_feet != nil }
            ?? insights?.recommendations?.first { $0.reason?.isEmpty == false }
        let pending = ScoreResponse(eligible: false, score: nil, tier: nil, s_perf: nil, a_acc: nil, c_cons: nil,
                                    p_power: nil, eligibility: nil, parts_delta_30d: nil, formula_version: nil, label: nil)
        var built = ShotResult(shotId: resp.shot_id, metrics: metrics, score: resp.score ?? pending,
                               footer: resp.footer, suggestedTarget: insights?.suggested_target,
                               recommendation: moveRec, insightsState: insights?.state,
                               insightsConfidence: insights?.confidence, insightsNote: insights?.note,
                               captureFarLaneLimited: record?.capture_quality?.far_lane == "limited",
                               captureReason: record?.capture_quality?.reason, isUpload: isUpload,
                               isForm: false, formView: nil, formStatus: nil, formVersion: nil)
        built.ballName = resp.shot.ball_name
        built.stageReport = record?.stage_report ?? [:]
        Self.attachShotCard(&built, record)
        built.engine = "iphone"
        return built
    }

    /// DEC-127 Offline Analysis: all on-device measurements shown, coaching marked pending (needs connectivity).
    /// No half-populated coaching — the view renders the measurements + one offline line and omits the coach box.
    private static func offlineResult(_ m: OnDeviceMeasurement, shotId: String, isUpload: Bool) -> ShotResult {
        let dict = metricDictFromDetailed(m.detailedJSON)
        let metrics: [(String, Metric)] = dict.isEmpty
            ? [("ball_speed", Metric(metric: "ball_speed", value: nil, unit: "mph", status: "unavailable",
                                     note: m.note.isEmpty ? "not measured on device" : m.note,
                                     confidence: nil, uncertainty: nil))]
            : MetricDisplay.ordered(dict)
        let pending = ScoreResponse(eligible: false, score: nil, tier: nil, s_perf: nil, a_acc: nil, c_cons: nil,
                                    p_power: nil, eligibility: nil, parts_delta_30d: nil, formula_version: nil, label: nil)
        var r = ShotResult(shotId: shotId, metrics: metrics, score: pending, footer: nil, suggestedTarget: nil,
                           recommendation: nil, insightsState: nil, insightsConfidence: nil, insightsNote: nil,
                           captureFarLaneLimited: false, captureReason: nil, isUpload: isUpload,
                           isForm: false, formView: nil, formStatus: nil, formVersion: nil)
        r.engine = "iphone"
        r.coachingPendingOffline = true
        return r
    }

    // MARK: - DEC-127 offline queue + background video upload

    /// Queue a metrics call that couldn't reach the server (offline). Stored as the exact /shots/metrics body;
    /// flushed when connectivity returns, which creates the server shot with coaching → it appears in history.
    private func enqueueMetricsCall(detailed: Data?, sessionId: String?, metadata: ShotMetadata, shotId: String) {
        guard let detailed, let detObj = (try? JSONSerialization.jsonObject(with: detailed)) as? [String: Any] else { return }
        let metaObj = (try? JSONSerialization.jsonObject(with: Data(metadata.jsonString().utf8))) ?? [:]
        var body: [String: Any] = ["metrics": detObj, "metadata": metaObj, "capture_mode": metadata.captureMode,
                                   "source": metadata.source, "algorithm_version": OnDeviceShadow.engineVersion,
                                   "shot_id": shotId]
        if let sessionId { body["session_id"] = sessionId }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var q = (defaults.array(forKey: "ls.metricsQueue") as? [Data]) ?? []
        q.append(data)
        defaults.set(q, forKey: "ls.metricsQueue")
    }

    /// Flush any queued metrics calls (call on launch / foreground). Each success creates the server shot with
    /// coaching; failures stay queued. Never blocks the UI and never mutates a screen the user is viewing.
    func flushMetricsQueue() {
        let q = (defaults.array(forKey: "ls.metricsQueue") as? [Data]) ?? []
        guard !q.isEmpty, let client = try? makeClient() else { return }
        Task.detached { [weak self] in
            var remaining: [Data] = []
            for body in q {
                do { _ = try await client.postMetricsRaw(body) }
                catch { remaining.append(body) }   // keep it for the next attempt
            }
            await MainActor.run { self?.defaults.set(remaining, forKey: "ls.metricsQueue") }
        }
    }

    /// DEC-127 #5: upload the clip in the BACKGROUND, after the result is shown — Wi-Fi only by default (a user
    /// setting allows cellular). Retention only here; the result is never changed by this. On cellular without
    /// permission the upload is skipped (the clip stays local for this run).
    private func backgroundUploadAndShadow(uploadURL: URL, originalURL: URL, metadata: ShotMetadata,
                                           sessionId: String?, shadowForShotId: String?, ct: [String: Double]) {
        let allowCellular = defaults.bool(forKey: "ls.cellular_upload")
        guard let client = try? makeClient() else { return }        // build on the main actor
        Task.detached {
            if await Reachability.isExpensive() && !allowCellular {
                // Wi-Fi only (default): defer. The on-device result + coaching already landed; the clip is kept
                // locally for this run. (A persistent Wi-Fi outbox is a follow-up.)
                return
            }
            do {
                let target = try await client.signedUploadURL()
                try await client.putClipToStorage(uploadURL: target.upload_url, fileURL: uploadURL) { _ in }
                // DEC-127: fire the server VIDEO shadow — it analyzes the clip for validation (a platform='server'
                // attempt + outcome rows for the SAME shot, so ops.engine_metric_agreement fills from real use)
                // and NEVER changes the shown result. Only when the online metrics call created a server shot.
                if let sid = shadowForShotId {
                    try? await client.shadowVideo(shotId: sid, storagePath: target.path)
                }
            } catch { /* best-effort; the result already landed */ }
            try? FileManager.default.removeItem(at: originalURL)
            if uploadURL != originalURL { try? FileManager.default.removeItem(at: uploadURL) }
        }
    }

    private func runPipeline(fileURL: URL, source: String) async {
        // Keep the upload + analyze request running if the user switches apps mid-analysis (iOS otherwise
        // suspends the app in a few seconds and the request dies). This buys the background-execution window;
        // the result is also durable server-side, so Lab › Uploads / the session still has it on return.
        var bgTask = UIApplication.shared.beginBackgroundTask(withName: "ls-analyze")
        func endBG() { if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid } }
        defer { endBG() }
        do {
            let client = try makeClient()
            // Snapshot the capture mode for THIS shot up front so detection later can't be confused by a
            // mode change while the clip is analyzing. This is also exactly what's sent as `capture_mode`.
            let capturedMode = captureMode
            // DEC-092 P0 (M1): phone-side per-stage timings. The pre-analyze parts (trim, upload) are the
            // wait the server can't see; they ride along with the analyze request onto the attempt row.
            let tTap = Date()
            var ct: [String: Double] = [:]

            // 1. Ensure a session exists for this app run — LIVE captures only. An upload (DEC-055) is a
            // STANDALONE analysis: it never creates or joins a session (so it stays out of Recent
            // sessions / activity and never feeds Stats, the Score, tiers or achievements).
            var sid: String? = nil
            if source == "live" {
                if let existing = sessionId {
                    sid = existing
                } else if !Self.onDevicePrimary {
                    pipeline = .creatingSession
                    let created = try await client.createSession(mode: "practice").id
                    sessionId = created
                    sid = created
                    track("session_started")   // §2 (DEC-098 M3): session auto-created on first live shot
                }
                // DEC-126: on-device primary — do NOT block the result on session creation (network). The session
                // is created in the background AFTER the on-device result is shown (below). Offline ⇒ stays nil
                // and the shot syncs standalone later.
            }

            // 2. Trim the clip to the shot window ON-DEVICE and fit it under the upload size cap. Both live
            // captures and Photos uploads go through this: the window trim is lossless (original fps +
            // resolution preserved, dead time at head/tail cut); only a clip still over the cap is re-encoded
            // to fit (bitrate only). This keeps uploads under Supabase's ~50 MB free-tier limit; the server
            // re-trims precisely afterwards.
            pipeline = .trimming
            let tTrim = Date()
            // DEC-101: Form clips are never window-trimmed (the start of the approach matters); Shot clips use the
            // head-only trim in VideoTrimmer (the tail always runs ≥10 s past motion onset so the ball reaches the pins).
            let (uploadURL, trimOutcome) = await VideoTrimmer.trimForUpload(fileURL, windowTrim: capturedMode != "form")
            ct["trim_s"] = Date().timeIntervalSince(tTrim)
            // Part 3d: record WHICH trim outcome fired (0/1 = trimmed, 2–6 = a named full-clip fallback, 7 =
            // form). A full-clip upload is no longer silent — ops can see why the window trim didn't cut.
            ct["trim_outcome"] = trimOutcome.rawValue
            // DEC-100: record what the phone trim kept, so a failure shows whether the trim cut the shot.
            if let d = await VideoTrimmer.duration(fileURL) { ct["orig_duration_s"] = d }
            if let d = await VideoTrimmer.duration(uploadURL) { ct["upload_duration_s"] = d }
            if let b = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int {
                ct["orig_bytes"] = Double(b)
            }
            if let b = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path))?[.size] as? Int {
                ct["upload_bytes"] = Double(b)
            }

            // DEC-127: build the shot metadata once — both the on-device-first path (the metrics call) and the
            // server-primary path (the upload) need it. Uploads seed the target from the Upload screen fields.
            if source != "live" {
                sessionTarget = ShotIntent(
                    feetBoard: Double(feetBoardText.trimmingCharacters(in: .whitespaces)),
                    arrowsBoard: Double(arrowsBoardText.trimmingCharacters(in: .whitespaces)),
                    breakpointBoard: Double(breakpointBoardText.trimmingCharacters(in: .whitespaces)))
                sessionSuggested = nil      // uploads have no Apply-this-move proposal
            }
            let ball = currentBall
            let metadata = ShotMetadata(
                handed: handed, captureMode: capturedMode, source: source,
                intent: sessionTarget, suggested: sessionSuggested,
                ballConfigurationId: ball?.ball_configuration_id, userBallId: ball?.id,
                oilPatternId: source == "live" ? selectedOilPatternId : nil)   // DEC-097: lock oil per live shot
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

            // ===================== DEC-127: ON-DEVICE-FIRST PATH (ball shots) =====================
            // The phone computes ALL metrics locally (speed, rev, boards, the lateral path), then a lightweight
            // metrics-only call returns Score + coaching. The result renders ONCE — a COMPLETE card online, an
            // OFFLINE card if the call doesn't return in 10 s — never piecemeal, never a half-filled screen. The
            // clip uploads AFTERWARD in the background (Wi-Fi only by default) and never changes what was shown.
            // No network is touched before the result (tap→result works with Wi-Fi off). Form keeps the server path.
            if Self.onDevicePrimary && capturedMode != "form" {
                pipeline = .analyzing(state: "ondevice", timings: [:])          // "Analyzing your shot"
                let tOD = Date()
                let od = await measureOnDevicePrimary(clipURL: uploadURL, shotId: UUID().uuidString,
                                                      source: source, sessionId: nil, mode: "shot")
                ct["ondevice_s"] = Date().timeIntervalSince(tOD)
                let m = od ?? OnDeviceMeasurement(ballSpeed: nil, foulToPins: nil, revRate: nil, basis: "unavailable",
                                                  note: "on-device analysis didn't finish within 30 s", latencyS: -1)
                let newShotId = UUID().uuidString
                if source == "live" && sid == nil {                            // session feeds the Score; best-effort
                    sid = try? await client.createSession(mode: "practice").id
                    if sid != nil { sessionId = sid; track("session_started") }
                }
                let detailed = m.detailedJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
                let traj = m.trajectoryJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
                var built: ShotResult
                var serverShotId: String? = nil        // set only when the online metrics call created a server shot
                if let detailed {
                    pipeline = .analyzing(state: "coaching", timings: [:])     // "Generating coaching"
                    do {
                        let resp = try await client.scoreFromMetrics(
                            metricsDetailed: detailed, trajectory: traj, keyPoints: nil,
                            sessionId: (source == "upload" ? nil : sid), metadata: metadata,
                            devicePerf: ["latency_s": m.latencyS], algorithmVersion: OnDeviceShadow.engineVersion,
                            appVersion: appVersion, timeoutS: 10)
                        built = Self.buildResultFromCard(resp, isUpload: source != "live")   // Complete Analysis
                        serverShotId = resp.shot_id
                        track("ondevice_metrics_complete",
                              props: ["ondevice_s": ct["ondevice_s"] ?? 0, "basis": m.basis, "engine": "iphone"])
                    } catch {
                        built = Self.offlineResult(m, shotId: newShotId, isUpload: source != "live")   // Offline
                        enqueueMetricsCall(detailed: m.detailedJSON, sessionId: (source == "upload" ? nil : sid),
                                           metadata: metadata, shotId: newShotId)
                        track("ondevice_offline_shown", props: ["ondevice_s": ct["ondevice_s"] ?? 0])
                    }
                } else {
                    built = Self.offlineResult(m, shotId: newShotId, isUpload: source != "live")   // engine couldn't measure
                }
                result = built                                                 // render ONCE ("Your results")
                if source == "live" { shotCount += 1; if shotCount == 1 { track("first_shot_analyzed") } }
                pipeline = .done
                showResult = true
                clearPendingAnalysis()
                // Background: upload the clip (Wi-Fi only by default) + fire the server VIDEO shadow for the
                // server-side comparison (platform='server' rows for the SAME shot). Shadow only when online.
                backgroundUploadAndShadow(uploadURL: uploadURL, originalURL: fileURL, metadata: metadata,
                                          sessionId: (source == "upload" ? nil : sid),
                                          shadowForShotId: serverShotId, ct: ct)
                return
            }

            // ==================== server-primary path (kill switch: on-device OFF) ====================
            // 3. Upload the clip (multipart) with progress, then analyze from Storage (no API request-size cap).
            let tUrl = Date()
            let target = try await client.signedUploadURL()
            ct["signed_url_s"] = Date().timeIntervalSince(tUrl)
            let tUp = Date()
            try await client.putClipToStorage(uploadURL: target.upload_url, fileURL: uploadURL) { [weak self] frac in
                self?.pipeline = .uploading(frac)
            }
            ct["upload_s"] = Date().timeIntervalSince(tUp)

            // 4. Analyze. The Phase-1 backend runs the CV INLINE, so this one request blocks for the whole
            //    analysis — we show the processing state for its full duration (treated as async in the UI;
            //    the result is durable in Supabase). `sessionId` nil → standalone upload; set → live shot.
            pipeline = .analyzing(state: "running", timings: [:])
            // Mark the in-flight analysis so a backgrounded/dropped request can be recovered on resume.
            markPendingAnalysis(source: source, sessionId: (source == "upload" ? nil : sid))
            ct["client_pre_analyze_s"] = Date().timeIntervalSince(tTap)   // tap-stop → analyze request sent
            let created = try await client.analyzeFromStorage(
                storagePath: target.path,
                sessionId: (source == "upload" ? nil : sid),
                metadata: metadata,
                clientTimings: ct)

            // DEC-106 shadow: run the native on-device engine on the same clip in the background and record it
            // (platform='ios') for engine comparison. Never shown to the user, never scored. Ball shots only.
            launchShadow(clipURL: uploadURL, shotId: created.shot_id, source: source,
                         sessionId: (source == "upload" ? nil : sid))

            // Synchronous backend ⇒ the job is already terminal; one fetch gets its state + timings footer.
            // Best-effort ONLY for a DECODE hiccup — the shot record is the source of truth after analysis. A job
            // with state=failed (or any transport error) must NEVER be swallowed; it has to surface the DEC-086
            // failure + Retry, not silently drop the user back to Upload (P0 2026-10-29).
            let last: JobResponse?
            do {
                last = try await client.job(created.job_id)
            } catch let e as APIError {
                if case .decoding = e { last = nil } else { throw e }   // tolerate a schema drift; rethrow the rest
            }
            if last?.state == "failed" {
                // DEC-086: show the server's friendly, user-facing copy — never the raw code/reason.
                let friendly = last?.failure?.display
                pipeline = .failed(friendly?.isEmpty == false ? friendly!
                                   : "We couldn't analyze this clip. Try recording the full shot with the lane in view.")
                clearPendingAnalysis()      // a real analysis failure — nothing to recover
                return
            }
            pipeline = .analyzing(state: last?.state ?? "done", timings: last?.timings?.values ?? [:])

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
                                   footer: isForm ? nil : last?.result,
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
            built.ballName = currentBall?.displayName    // DEC-097: live shot uses the ball at record time
            built.stageReport = record?.stage_report ?? [:]     // DEC-122 "What worked" (dev/TestFlight)
            if isForm { Self.attachFormFundamentals(&built, record) }
            else { Self.attachShotCard(&built, record) }
            // Server-primary path (DEC-127 kill switch OFF): the server CV is authoritative for everything here.
            result = built
            shotCount += 1
            // §2 (DEC-098 M3): first successful live shot in this session (uploads are standalone, no session).
            if source == "live", shotCount == 1 { track("first_shot_analyzed") }
            pipeline = .done
            showResult = true
            clearPendingAnalysis()      // delivered in-app; nothing to recover

            // Clean up the temp clips (the original recording and, if different, the trimmed upload).
            try? FileManager.default.removeItem(at: fileURL)
            if uploadURL != fileURL { try? FileManager.default.removeItem(at: uploadURL) }
        } catch {
            // DEC-100: the server never logged this one — report it so no failed attempt is invisible.
            let stage: String
            switch pipeline {
            case .creatingSession: stage = "session"
            case .trimming: stage = "trim"
            case .uploading: stage = "upload"
            case .analyzing: stage = "analyze_request"
            case .fetching: stage = "fetch_result"
            default: stage = "unknown"
            }
            var report: [String: Any] = [
                "stage": stage, "error": String(String(describing: error).prefix(500)),
                "source": source, "capture_mode": captureMode,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"]
            if source == "live", let sid = sessionId { report["session_id"] = sid }
            if let b = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int {
                report["clip_bytes"] = b
            }
            if let json = try? JSONSerialization.data(withJSONObject: report), let client = try? makeClient() {
                Task { try? await client.reportClientFailure(json) }    // best effort; never blocks the UI
            }
            // The on-device-first path returns before any throw and handles offline itself, so this catch is the
            // server-primary path (or an early trim/client error): surface the failure + Retry (DEC-086).
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
            built.ballName = shot.ball_name          // DEC-097: the ball this shot was thrown with
            built.stageReport = record?.stage_report ?? [:]     // DEC-122 "What worked" (dev/TestFlight)
            if isForm { Self.attachFormFundamentals(&built, record) }
            else { Self.attachShotCard(&built, record) }
            result = built
            return true
        } catch {
            return false
        }
    }

    /// Copies the form fundamentals v1 payload (DEC-057) from the shot record onto the result. Everything
    /// stays absent when the record didn't carry it — nothing is fabricated.
    /// DEC-088/090: copy the shot-card fields (fitted path, pinned points, Power, baseline, coach read) from
    /// the record onto the result. Ball shots only; everything stays nil when the record didn't carry it.
    private static func attachShotCard(_ r: inout ShotResult, _ record: ShotRecord?) {
        guard let record, record.form_version == nil else { return }
        r.pathFit = record.path_fit
        r.keyPoints = record.key_points ?? [:]
        r.baseline = record.baseline
        r.impactEnergyJ = record.impact_energy_j
        r.coachThrow = record.insights?.throwRead
        r.coachLane = record.insights?.lane
        r.coachAction = record.insights?.coach
    }

    private static func attachFormFundamentals(_ r: inout ShotResult, _ record: ShotRecord?) {
        guard let record else { return }
        r.formFPS = record.fps
        r.keyFrames = record.key_frames ?? []
        r.keyFramePoses = record.key_frame_poses ?? [:]
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
        uploadBusy = false
    }

    // MARK: recover-on-resume (an analysis that was in flight when the app was backgrounded)

    private func markPendingAnalysis(source: String, sessionId: String?) {
        pendingAnalysis = PendingAnalysis(source: source, sessionId: sessionId, startedAt: Date().timeIntervalSince1970)
    }
    func clearPendingAnalysis() { pendingAnalysis = nil }

    /// Called when the app returns to the foreground. If an analysis was in flight when we were backgrounded,
    /// the server likely finished it (the result is durable in Supabase) even though our request dropped — so
    /// fetch the shot the server was working on and present its result (or its failure), instead of leaving the
    /// user on a stale "failed". If it's still running, re-raise the analyzing cover and keep the marker.
    /// Find the shot the dropped analysis was working on + its current state (analyzed/failed/running). Recovery
    /// is keyed on the SHOT (durable in Supabase), not the in-flight job id — in sync mode the job_id only comes
    /// back on completion, which a dropped request never saw. Returns nil while still offline / nothing yet.
    private func latestPendingShot(_ pending: PendingAnalysis, _ client: APIClient)
        async -> (id: String, hint: String?, state: String?)? {
        do {
            if pending.source == "upload" {
                let rows = try await client.listUploads()
                let c = rows.filter { ($0.created_at ?? 0) >= pending.startedAt - 5 }
                    .max { ($0.created_at ?? 0) < ($1.created_at ?? 0) }
                    ?? rows.max { ($0.created_at ?? 0) < ($1.created_at ?? 0) }
                guard let c else { return nil }
                return (c.id, c.capture_mode, c.state)
            } else {
                let rows = try await client.sessionShots(pending.sessionId ?? "")
                guard let c = rows.filter({ ($0.created_at ?? 0) >= pending.startedAt - 5 })
                    .max(by: { ($0.created_at ?? 0) < ($1.created_at ?? 0) }) else { return nil }
                return (c.id, nil, c.state)                  // live: loadShotResult detects form from the record
            }
        } catch { return nil }
    }

    func reconcilePendingAnalysis(coldLaunch: Bool = false) async {
        guard let pending = pendingAnalysis, let client = try? makeClient() else { return }
        guard let found = await latestPendingShot(pending, client) else { return }
        let sid = found.id, hint = found.hint, state = found.state
        // COLD LAUNCH (2026-10-30): the app was CLOSED — land on Home and surface the finished/failed shot
        // non-intrusively as an "away" banner (it's already durable in Lab › Uploads / the session list), never
        // a result sheet at launch. A still-running one just stays pending and appears in its row when it lands.
        if coldLaunch {
            switch state {
            case "analyzed": awayResult = AwayResult(shotId: sid, mode: hint, failed: false, sessionId: pending.sessionId); clearPendingAnalysis()
            case "failed":   awayResult = AwayResult(shotId: sid, mode: hint, failed: true,  sessionId: pending.sessionId); clearPendingAnalysis()
            default:         break   // still running → leave the marker; it surfaces in its row when done
            }
            return
        }
        switch state {
        case "analyzed":
            if await loadShotResult(shotId: sid, captureModeHint: hint) {
                pipeline = .done; uploadBusy = true          // present the recovered result at the app root
            }
            clearPendingAnalysis()
        case "failed":
            pipeline = .failed("We couldn't analyze that shot."); uploadBusy = true
            clearPendingAnalysis()
        default:
            // Still running. Raise the analyzing cover AND actively poll the shot state to completion, so the
            // user doesn't have to background/foreground again for the result to land (Part 3b resume-polling).
            pipeline = .analyzing(state: "running", timings: [:]); uploadBusy = true
            await resumePoll(pending: pending, client: client, hint: hint)
        }
    }

    /// Bounded poll of the pending shot's state until terminal (≈3 min at 4 s). Presents the result/failure the
    /// moment the server finishes — in-app, no second foreground needed. Stops early if the marker is cleared
    /// (e.g. the user started a new shot) so we never hijack a later analysis.
    private func resumePoll(pending: PendingAnalysis, client: APIClient, hint: String?) async {
        for _ in 0..<45 {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard pendingAnalysis?.startedAt == pending.startedAt else { return }   // superseded/cleared → stop
            guard let found = await latestPendingShot(pending, client) else { continue }
            switch found.state {
            case "analyzed":
                if await loadShotResult(shotId: found.id, captureModeHint: hint ?? found.hint) {
                    pipeline = .done; uploadBusy = true
                }
                clearPendingAnalysis(); return
            case "failed":
                pipeline = .failed("We couldn't analyze that shot."); uploadBusy = true
                clearPendingAnalysis(); return
            default: continue                                 // still running → keep polling
            }
        }
    }

    var activeSessionId: String? { sessionId }

    /// Fire-and-forget warm-up ping so the scale-to-zero Cloud Run instance is already running by the time
    /// the first clip uploads — otherwise the first analysis of a session eats a ~15–30s cold start. Best
    /// effort: failures are ignored (it's only an optimization).
    private var lastPrewarm: Date = .distantPast
    func prewarm() {
        // DEC-092 P0 (D2): at most once per ~5 min — enough to keep the scale-to-zero instance warm through
        // setup + the first shot without hammering /health.
        guard Date().timeIntervalSince(lastPrewarm) > 300 else { return }
        lastPrewarm = Date()
        guard let client = try? makeClient() else { return }
        Task { _ = try? await client.health() }
    }

    /// Starts a new live session from the Setup screen (mode, lane, oil pattern) and resets counters.
    func startLiveSession(mode: String, lane: String?, oilPatternId: String?) async throws {
        prewarm()        // warm the instance while the bowler sets up for the first shot
        let client = try makeClient()
        let session = try await client.createSessionFull(mode: "practice", lanePair: lane, oilPatternId: oilPatternId)
        sessionId = session.id
        track("session_started")      // §2 (DEC-098 M3): explicit start from Setup
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
