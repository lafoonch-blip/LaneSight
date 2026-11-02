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
    case offlineQueued                     // DEC-119: no connection — clip is saved + will upload when online
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
final class AppModel: ObservableObject, BackgroundUploadObserver {
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

    // DEC-119 session durability --------------------------------------------------------------------------
    /// The one active session, mirrored from the server (`sessions.ended_at` null) and persisted locally so the
    /// banner + resume prompt survive relaunch / force-quit / offline. The Active Session screen always re-reads
    /// the authoritative shot list from the server.
    @Published private(set) var activeSession: PersistedSession?
    /// Set when a resume prompt should be shown: cold launch (post force-quit/crash) or foreground after ≥30 min
    /// in the background, with an active session. The app root presents a "Continue / End session" alert.
    struct ResumePrompt: Identifiable, Equatable { let id = UUID(); let session: PersistedSession }
    @Published var resumePrompt: ResumePrompt?
    /// A request to open the Active Session (Home banner tap, or "Continue" from the resume prompt). Drives the
    /// push on Home's stack; RootTabs switches to Home when it flips true, and pops it when you leave the Home tab.
    @Published var openActiveSessionRequest = false
    /// Same, for the Lab tab's banner (pushes on Lab's stack; popped when you leave Lab). Separate per tab so each
    /// Active Session push is transient — leaving a tab returns it to its own root (not a sticky detail).
    @Published var openActiveSessionFromLab = false
    /// The ShotUpload record id currently driving the foreground Analyzing cover (nil for background work).
    private var foregroundUploadId: String?
    /// Records with an upload PUT in flight / an analyze request in flight. Guards against the several resume
    /// triggers (scenePhase, RootTabs task, Connectivity) each (re)starting the same record concurrently —
    /// which would duplicate the upload and, worse, the analyze → duplicate shots server-side.
    private var inFlightUploads: Set<String> = []
    private var inFlightAnalyze: Set<String> = []
    // -----------------------------------------------------------------------------------------------------

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
        static let activeSession = "ls.activeSession"       // DEC-119 persisted active-session mirror
        static let backgroundedAt = "ls.backgroundedAt"     // DEC-119 last background-enter time (resume decision)
        static let ffConsent = "ls.ffConsentVersion"        // DEC-123 accepted F&F consent version (local gate)
    }

    // MARK: DEC-123 Friends & Family phase / owner gating ------------------------------------------------
    /// The current F&F consent version. Bump when the consent copy materially changes so testers re-accept.
    static let ffConsentVersion = "ff-2026-11-02"
    /// The build's declared phase (Debug → dev, F&F TestFlight Release → ff). Sent on feedback and, for F&F,
    /// written to the account cohort at consent. The server cohort is authoritative (owner/staged forced dev).
    var appPhase: String { AppPhase.current.rawValue }
    /// True only for Shayne's account (or the dev-user escape hatch). Owner-only screens — the Dev build panel
    /// and test-account switching — are hidden from F&F testers unless this is true (DEC-123).
    var isOwner: Bool { useDevUser || session?.user_id == Owner.userID }
    /// The F&F consent the tester has accepted on this device (nil = not accepted). Persisted locally so the
    /// one-screen consent shows once; the version + timestamp are also stored on the account (migration 036).
    @Published private(set) var ffConsentAcceptedVersion: String? {
        didSet { defaults.set(ffConsentAcceptedVersion, forKey: Keys.ffConsent) }
    }
    /// Show the one-screen F&F consent: an F&F build, signed in, and the current consent not yet accepted.
    var needsFFConsent: Bool {
        AppPhase.current.requiresFFConsent && session != nil
            && ffConsentAcceptedVersion != Self.ffConsentVersion
    }

    /// DEC-119: ≥30 min in the background (with an active session) prompts Continue/End on return; shorter gaps
    /// return straight to where the user was.
    nonisolated static let resumePromptBackgroundThreshold: TimeInterval = 30 * 60

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
        ffConsentAcceptedVersion = defaults.string(forKey: Keys.ffConsent)

        // Restore a persisted Keychain session (tokens survive relaunch; cleared on sign out).
        if let access = Keychain.get(Keychain.Account.accessToken) {
            session = AuthSession(access_token: access,
                                  refresh_token: Keychain.get(Keychain.Account.refreshToken),
                                  expires_in: nil,
                                  user_id: Keychain.get(Keychain.Account.userId))
        }

        // DEC-119: restore the persisted active session (survives force-quit/crash) and become the background
        // upload manager's observer so in-flight / resumed transfers report progress + completion here.
        if let d = defaults.data(forKey: Keys.activeSession),
           let s = try? JSONDecoder().decode(PersistedSession.self, from: d) {
            activeSession = s
            sessionId = s.id
            captureMode = s.mode
        }
        BackgroundUploadManager.shared.observer = self
    }

    // MARK: DEC-119 active-session mirror

    private func persistActiveSession() {
        if let s = activeSession, let d = try? JSONEncoder().encode(s) {
            defaults.set(d, forKey: Keys.activeSession)
        } else {
            defaults.removeObject(forKey: Keys.activeSession)
        }
    }

    /// Records a newly-created session as the one active session and persists the mirror.
    private func setActiveSession(id: String, mode: String, startedAt: Double) {
        activeSession = PersistedSession(id: id, mode: mode, startedAt: startedAt, shotCount: shotCount)
        sessionId = id
        persistActiveSession()
    }

    /// Server is the source of truth for "active" (DEC-119): reconcile the local mirror with `sessions.ended_at`.
    /// Offline (list fails) → keep the local mirror untouched. Called on authed load + on foreground.
    func refreshActiveSessionFromServer() async {
        guard let client = try? makeClient() else { return }
        guard let rows = try? await client.listSessions() else { return }   // offline → keep local mirror
        if let live = rows.first(where: { $0.ended_at == nil }) {
            let count = (activeSession?.id == live.id) ? (activeSession?.shotCount ?? 0) : 0
            activeSession = PersistedSession(id: live.id,
                                             mode: live.capture_mode ?? captureMode,
                                             startedAt: live.started_at ?? Date().timeIntervalSince1970,
                                             shotCount: count)
            sessionId = live.id
            persistActiveSession()
            ls119log("active-session mirror ← server id=\(live.id) shots=\(count)")
        } else if activeSession != nil {
            // The server has no active session (it was ended elsewhere) → drop the stale local mirror.
            activeSession = nil
            sessionId = nil
            persistActiveSession()
            ls119log("active-session mirror cleared (server shows none active)")
        }
    }

    // MARK: DEC-119 background / resume lifecycle

    /// Call when the app enters the background: stamp the time so a ≥30 min absence can prompt on return.
    func noteDidEnterBackground() {
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.backgroundedAt)
    }

    /// Decide whether to show the Continue/End resume prompt. Cold launch (post force-quit/crash) always prompts
    /// when a session is active; a warm foreground prompts only after ≥30 min in the background. Shorter gaps
    /// return straight back with no prompt.
    func evaluateResumeOnForeground(coldLaunch: Bool) {
        let bg = defaults.double(forKey: Keys.backgroundedAt)
        defaults.removeObject(forKey: Keys.backgroundedAt)
        guard let s = activeSession else { return }
        if Self.shouldPromptResume(coldLaunch: coldLaunch, backgroundedAt: bg,
                                   now: Date().timeIntervalSince1970, hasActiveSession: true) {
            resumePrompt = ResumePrompt(session: s)
            ls119log("resume PROMPT shown (cold=\(coldLaunch), session=\(s.id), shots=\(s.shotCount))")
        } else {
            ls119log("resume: no prompt (cold=\(coldLaunch), bgStamp=\(bg), session=\(s.id))")
        }
    }

    /// Pure resume-prompt decision (DEC-119), separated for testing: cold launch (post force-quit/crash) always
    /// prompts when a session is active; a warm foreground prompts only after ≥30 min in the background.
    nonisolated static func shouldPromptResume(coldLaunch: Bool, backgroundedAt: Double?, now: Double,
                                               hasActiveSession: Bool) -> Bool {
        guard hasActiveSession else { return false }
        if coldLaunch { return true }
        guard let bg = backgroundedAt, bg > 0 else { return false }
        return now - bg >= resumePromptBackgroundThreshold
    }

    /// "Continue" from the resume prompt (or a banner tap): open the Active Session.
    func resumePromptContinue() {
        resumePrompt = nil
        openActiveSessionRequest = true
    }

    /// "End session" from the resume prompt: close the session (becomes history; summary/feedback skipped per
    /// DEC-119) and stay on Home.
    func resumePromptEnd() async {
        resumePrompt = nil
        try? await endCurrentSession()
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
        // DEC-119: drop the active-session mirror + any durable upload records/clips for this account.
        activeSession = nil
        resumePrompt = nil
        persistActiveSession()
        ShotUploadStore.shared.purgeAll()
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
        // DEC-099: save the ORIGINAL recording to Photos first (before trimming/cleanup), so the bowler keeps
        // the clip even if the analysis fails. Never blocks the analysis on a Photos error.
        if saveVideosToPhone { _ = await Self.saveVideoToPhotos(fileURL) }
        await enqueueAndStart(originalURL: fileURL, source: "live")
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
        pipeline = .trimming
        uploadBusy = true
        await enqueueAndStart(originalURL: fileURL, source: "upload")
    }

    /// DEC-096/119: retry the foreground shot after a failure — no re-recording. Resumes from wherever the
    /// durable record stalled (re-upload if the upload failed, re-analyze if the upload had succeeded).
    func retryLastAnalysis() async {
        guard let id = foregroundUploadId, let rec = ShotUploadStore.shared.load(id) else { return }
        if rec.source == "upload" { uploadBusy = true }
        switch rec.state {
        case .uploaded, .analyzing:
            await runAnalyze(id: id)
        default:
            // reset the backoff so Retry starts the upload immediately
            var r = rec; r.attempts = 0; r.nextAttemptAt = 0; r.state = .pending; ShotUploadStore.shared.save(r)
            await startUpload(id: id)
        }
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

    // MARK: DEC-119 persist-before-upload → background upload → analyze

    /// DEC-119 item 3/4. The moment recording finishes (BEFORE any upload): copy the clip to a durable dir and
    /// write a ShotUpload record, so a kill/crash/force-quit between here and a completed upload can't lose it
    /// (the 13:56 bug). Then trim on-device and hand the clip to the background URLSession.
    private func enqueueAndStart(originalURL: URL, source: String) async {
        let capturedMode = captureMode
        let tTap = Date()

        // 1. Snapshot the target (uploads seed theirs from the Upload screen's fields) + build the metadata that
        //    is LOCKED for this shot (ball / oil / target at record time), serialized for durability.
        if source != "live" {
            sessionTarget = ShotIntent(
                feetBoard: Double(feetBoardText.trimmingCharacters(in: .whitespaces)),
                arrowsBoard: Double(arrowsBoardText.trimmingCharacters(in: .whitespaces)),
                breakpointBoard: Double(breakpointBoardText.trimmingCharacters(in: .whitespaces)))
            sessionSuggested = nil
        }
        let ball = currentBall
        let metadata = ShotMetadata(
            handed: handed, captureMode: capturedMode, source: source,
            intent: sessionTarget, suggested: sessionSuggested,
            ballConfigurationId: ball?.ball_configuration_id, userBallId: ball?.id,
            oilPatternId: source == "live" ? selectedOilPatternId : nil)

        // 2. Persist the clip + record immediately (durable). clipPath starts as the ORIGINAL copy; if the trim
        //    succeeds we swap in the trimmed clip. Either way the clip is safe before the upload begins.
        let id = UUID().uuidString
        let ext = originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension
        let durable = ShotUploadStore.shared.durableClipURL(for: id, ext: ext)
        try? FileManager.default.removeItem(at: durable)
        do { try FileManager.default.copyItem(at: originalURL, to: durable) }
        catch {
            // Couldn't copy to the durable dir — fall back to the original path so we still upload something.
            if (try? FileManager.default.copyItem(at: originalURL, to: durable)) == nil {}
        }
        let clipPath = FileManager.default.fileExists(atPath: durable.path) ? durable.path : originalURL.path
        var rec = ShotUpload(id: id, sessionId: (source == "live" ? sessionId : nil), source: source,
                             captureMode: capturedMode, createdAt: Date().timeIntervalSince1970,
                             clipPath: clipPath, state: .pending, storagePath: nil, uploadURL: nil,
                             metadataJSON: metadata.jsonString(), clientTimingsJSON: nil,
                             attempts: 0, nextAttemptAt: 0, lastError: nil)
        ShotUploadStore.shared.save(rec)
        foregroundUploadId = id
        lastCaptureURL = URL(fileURLWithPath: clipPath)
        lastSource = source
        ls119log("enqueue id=\(id) source=\(source) persisted clip=\(clipPath) state=pending")

        // 3. Trim on-device (DEC-101: form clips keep the full approach; shot clips window-trim). Swap the
        //    durable clip for the trimmed one so the kept clip == what we upload.
        pipeline = .trimming
        var ct: [String: Double] = [:]
        let tTrim = Date()
        let clipURL = URL(fileURLWithPath: clipPath)
        let (trimmedURL, trimOutcome) = await VideoTrimmer.trimForUpload(clipURL, windowTrim: capturedMode != "form")
        ct["trim_s"] = Date().timeIntervalSince(tTrim)
        ct["trim_outcome"] = trimOutcome.rawValue
        if trimmedURL != clipURL {
            try? FileManager.default.removeItem(at: clipURL)
            if (try? FileManager.default.moveItem(at: trimmedURL, to: clipURL)) == nil {
                // move failed — upload the trimmed temp directly and point the record at it
                rec.clipPath = trimmedURL.path
                lastCaptureURL = trimmedURL
            }
        }
        if let d = await VideoTrimmer.duration(clipURL) { ct["upload_duration_s"] = d }
        if let b = (try? FileManager.default.attributesOfItem(atPath: rec.clipPath))?[.size] as? Int { ct["upload_bytes"] = Double(b) }
        ct["client_pre_analyze_s"] = Date().timeIntervalSince(tTap)
        rec.clientTimingsJSON = String(data: (try? JSONSerialization.data(withJSONObject: ct)) ?? Data(), encoding: .utf8)
        ShotUploadStore.shared.save(rec)

        // Original tmp recording is no longer needed (we hold a durable copy).
        if originalURL.path != rec.clipPath { try? FileManager.default.removeItem(at: originalURL) }

        // 4. Sign + start the background upload.
        pipeline = .uploading(0)
        await startUpload(id: id)
    }

    /// (Re)start the background PUT for a record. Ensures a session for live shots (survives offline via retry),
    /// (re-)signs a fresh Storage URL (the previous one may have expired), then hands the clip to the background
    /// URLSession so the transfer survives app suspension.
    private func startUpload(id: String) async {
        guard !inFlightUploads.contains(id) else { return }   // already uploading — don't double-start
        guard var rec = ShotUploadStore.shared.load(id), !rec.isTerminal else { return }
        inFlightUploads.insert(id)
        do {
            let client = try makeClient()
            // Live shots need a session; create one lazily and record it as the active session (persisted).
            if rec.source == "live", rec.sessionId == nil {
                if let existing = sessionId {
                    rec.sessionId = existing
                } else {
                    pipeline = (foregroundUploadId == id) ? .creatingSession : pipeline
                    let created = try await client.createSession(mode: "practice").id
                    setActiveSession(id: created, mode: rec.captureMode, startedAt: Date().timeIntervalSince1970)
                    rec.sessionId = created
                    track("session_started")
                }
            }
            let target = try await client.signedUploadURL()
            rec.storagePath = target.path
            rec.uploadURL = target.upload_url
            rec.state = .uploading
            ShotUploadStore.shared.save(rec)
            if foregroundUploadId == id { pipeline = .uploading(0) }
            BackgroundUploadManager.shared.observer = self
            BackgroundUploadManager.shared.start(rec)
            ls119log("upload start id=\(id) session=\(rec.sessionId ?? "nil") signed-ok")
        } catch {
            // Can't sign / create a session. The clip is safe on disk; keep the record pending and retry.
            inFlightUploads.remove(id)   // the PUT never started; allow a later (re)start
            rec.attempts += 1
            rec.state = .pending
            rec.lastError = String(String(describing: error).prefix(200))
            rec.nextAttemptAt = Date().timeIntervalSince1970 + UploadBackoff.delay(attempt: rec.attempts)
            ShotUploadStore.shared.save(rec)
            // Offline/transport is NOT a terminal failure (DEC-119): never mark the record `.failed` for it —
            // a `.failed` record wouldn't auto-resume, which would lose the shot. Stay `.pending`, tell the user
            // it's saved + queued, and let reconnect / foreground resume it. Only a NON-transport error can hit
            // the terminal cap (e.g. a persistent bad response).
            if isTransport(error) {
                if foregroundUploadId == id { pipeline = .offlineQueued }
                ls119log("upload offline id=\(id) → queued pending (attempt \(rec.attempts)); will resume on reconnect")
                scheduleUploadRetry(id: id)
            } else if rec.attempts >= UploadBackoff.maxAttempts {
                failUpload(id: id, message: rec.lastError ?? "Upload failed")
            } else {
                if foregroundUploadId == id { pipeline = .uploading(0) }
                scheduleUploadRetry(id: id)
            }
        }
    }

    /// True for a connectivity/transport error (offline, timeout, lost connection) — recoverable, not terminal.
    private func isTransport(_ error: Error) -> Bool {
        if case APIError.transport = error { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }

    /// Re-run the upload after the record's backoff elapses. Self-healing: if the app is killed during the wait,
    /// resume() on relaunch re-starts the still-`pending` record anyway.
    private func scheduleUploadRetry(id: String) {
        guard let rec = ShotUploadStore.shared.load(id) else { return }
        let delay = max(0, rec.nextAttemptAt - Date().timeIntervalSince1970)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            guard let r = ShotUploadStore.shared.load(id), r.state == .pending else { return }
            await self.startUpload(id: id)
        }
    }

    /// Terminal upload failure: mark the record failed, report it to the server (DEC-100 `stage=upload`), and
    /// surface a friendly error + Retry if this is the foreground shot.
    private func failUpload(id: String, message: String) {
        guard var rec = ShotUploadStore.shared.load(id) else { return }
        rec.state = .failed
        rec.lastError = message
        ShotUploadStore.shared.save(rec)
        reportClientFailure(rec: rec, stage: "upload", error: message)
        ls119log("upload FAILED id=\(id) msg=\(message) → reported client-failure stage=upload")
        if foregroundUploadId == id {
            pipeline = .failed("We couldn't upload this clip. Check your connection and tap Retry.")
        }
    }

    /// DEC-100: report a client-side failure (`stage=upload` etc.) so no failed attempt is invisible in ops.
    private func reportClientFailure(rec: ShotUpload, stage: String, error: String) {
        var report: [String: Any] = [
            "stage": stage, "error": String(error.prefix(500)),
            "source": rec.source, "capture_mode": rec.captureMode,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"]
        if let sid = rec.sessionId { report["session_id"] = sid }
        if let b = (try? FileManager.default.attributesOfItem(atPath: rec.clipPath))?[.size] as? Int { report["clip_bytes"] = b }
        if let json = try? JSONSerialization.data(withJSONObject: report), let client = try? makeClient() {
            Task { try? await client.reportClientFailure(json) }
        }
    }

    // MARK: BackgroundUploadObserver (DEC-119)

    func uploadProgress(id: String, fraction: Double) {
        guard foregroundUploadId == id else { return }     // background work doesn't drive the cover
        switch pipeline {
        case .uploading, .trimming, .creatingSession: pipeline = .uploading(fraction)
        default: break
        }
    }

    func uploadFinished(id: String, outcome: UploadOutcome) {
        ls119log("upload finished id=\(id) outcome=\(outcome) appState=\(UIApplication.shared.applicationState.rawValue)")
        inFlightUploads.remove(id)   // this PUT task is done (success or failure)
        guard var rec = ShotUploadStore.shared.load(id), !rec.isTerminal else { return }
        switch outcome {
        case .success:
            rec.state = .uploaded
            rec.attempts = 0
            ShotUploadStore.shared.save(rec)
            // Run the analyze request in the foreground where it has a full window. If we were only woken in the
            // background for the transfer event, leave it `uploaded`; resume() analyzes on the next foreground.
            if UIApplication.shared.applicationState == .active {
                Task { await runAnalyze(id: id) }
            }
        case .transientFailure(let msg):
            rec.attempts += 1
            rec.lastError = msg
            if rec.attempts >= UploadBackoff.maxAttempts {
                ShotUploadStore.shared.save(rec)
                failUpload(id: id, message: msg)
            } else {
                rec.state = .pending
                rec.nextAttemptAt = Date().timeIntervalSince1970 + UploadBackoff.delay(attempt: rec.attempts)
                ShotUploadStore.shared.save(rec)
                scheduleUploadRetry(id: id)
            }
        case .permanentFailure(let msg):
            // Usually an expired signed URL — re-sign and retry a couple of times before giving up.
            rec.attempts += 1
            rec.lastError = msg
            if rec.attempts < 3 {
                rec.state = .pending
                rec.nextAttemptAt = Date().timeIntervalSince1970 + UploadBackoff.delay(attempt: rec.attempts)
                ShotUploadStore.shared.save(rec)
                scheduleUploadRetry(id: id)
            } else {
                ShotUploadStore.shared.save(rec)
                failUpload(id: id, message: msg)
            }
        }
    }

    /// Analyze an uploaded clip and deliver its result. Once the analyze request is sent, the result is durable
    /// server-side (DEC-110) even if this request drops — so we also set the pendingAnalysis marker and only
    /// remove the durable upload record after the analyze request returns.
    private func runAnalyze(id: String) async {
        guard !inFlightAnalyze.contains(id) else { return }   // one analyze per record (guards duplicate shots)
        guard var rec = ShotUploadStore.shared.load(id), !rec.isTerminal,
              let storagePath = rec.storagePath else { return }
        inFlightAnalyze.insert(id)
        defer { inFlightAnalyze.remove(id) }
        let present = (foregroundUploadId == id)
        // Keep the analyze request alive briefly if the user switches away (iOS otherwise suspends in seconds).
        var bgTask = UIApplication.shared.beginBackgroundTask(withName: "ls-analyze")
        func endBG() { if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid } }
        defer { endBG() }
        if present { pipeline = .analyzing(state: "running", timings: [:]) }
        // Persist `.analyzing` BEFORE the POST so a kill mid-analysis is recovered by a shot-existence check on
        // resume (not a blind re-POST, which could duplicate a shot the server already started — DEC-110).
        rec.state = .analyzing
        ShotUploadStore.shared.save(rec)
        markPendingAnalysis(source: rec.source, sessionId: (rec.source == "upload" ? nil : rec.sessionId))
        ls119log("analyze start id=\(id) present=\(present)")
        do {
            let client = try makeClient()
            let metaObj = (try? JSONSerialization.jsonObject(with: Data(rec.metadataJSON.utf8))) as? [String: Any] ?? [:]
            let ct = rec.clientTimingsJSON.flatMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Double]
            }
            let created = try await client.analyzeFromStorage(
                storagePath: storagePath,
                sessionId: (rec.source == "upload" ? nil : rec.sessionId),
                metadataObject: metaObj, clientTimings: ct)

            // DEC-106 shadow on the same durable clip (ball shots only; never shown/scored).
            launchShadow(clipURL: rec.clipURL, shotId: created.shot_id, source: rec.source,
                         sessionId: (rec.source == "upload" ? nil : rec.sessionId))

            // Synchronous backend ⇒ the job is terminal; fetch its state + footer (tolerate a schema drift).
            let last: JobResponse?
            do { last = try await client.job(created.job_id) }
            catch let e as APIError { if case .decoding = e { last = nil } else { throw e } }
            if last?.state == "failed" {
                let friendly = last?.failure?.display
                if present {
                    pipeline = .failed(friendly?.isEmpty == false ? friendly!
                        : "We couldn't analyze this clip. Try recording the full shot with the lane in view.")
                }
                clearPendingAnalysis()
                ShotUploadStore.shared.remove(id)        // a real analysis failure — nothing left to recover
                return
            }

            // Build + deliver the result (footer carried only for the foreground shot).
            if present {
                if await loadShotResult(shotId: created.shot_id, captureModeHint: rec.captureMode) {
                    if var r = result { r.footer = last?.result; result = r }
                    pipeline = .done
                    showResult = true
                }
            }
            shotCount += 1
            if activeSession != nil { activeSession?.shotCount = shotCount; persistActiveSession() }
            if rec.source == "live", shotCount == 1 { track("first_shot_analyzed") }
            clearPendingAnalysis()
            ShotUploadStore.shared.remove(id)            // delivered (or durable server-side) — drop record + clip
            ls119log("analyze done id=\(id) shot=\(created.shot_id) delivered; record removed")
        } catch {
            // Analyze request dropped/failed. The result is durable server-side; leave the record `uploaded` so
            // resume can re-run analyze, and keep the pendingAnalysis marker so reconcile can recover it too.
            ls119log("analyze error id=\(id) err=\(error.localizedDescription) (record kept uploaded for resume)")
            if present { pipeline = .failed(error.localizedDescription) }
        }
    }

    /// Recover a record that was mid-analyze when the app died. If the shot already exists server-side (durable
    /// job/shot, DEC-110) it will show up in the session/uploads list — drop the record. If no shot exists (the
    /// analyze POST never landed), re-run analyze. This avoids duplicating a shot the server already started.
    private func recoverAnalyzing(id: String) async {
        guard !inFlightAnalyze.contains(id) else { return }   // an analyze is already running for this id
        guard let rec = ShotUploadStore.shared.load(id), rec.state == .analyzing,
              let client = try? makeClient() else { return }
        let pending = PendingAnalysis(source: rec.source,
                                      sessionId: (rec.source == "upload" ? nil : rec.sessionId),
                                      startedAt: rec.createdAt)
        if let found = await latestPendingShot(pending, client) {
            ls119log("resume analyzing id=\(id) → shot \(found.id) exists server-side (\(found.state ?? "?")); record dropped")
            clearPendingAnalysis()
            ShotUploadStore.shared.remove(id)
        } else {
            ls119log("resume analyzing id=\(id) → no shot server-side; re-running analyze")
            var r = rec; r.state = .uploaded; ShotUploadStore.shared.save(r)
            await runAnalyze(id: id)
        }
    }

    /// DEC-119 item 3/4: resume durable uploads/analyses on relaunch or foreground. Reconnects the background
    /// URLSession, (re)starts stalled uploads, and runs analyze for clips that finished uploading while away.
    func resumePendingUploads() async {
        BackgroundUploadManager.shared.observer = self
        let live = await BackgroundUploadManager.shared.liveTaskIDs()
        let pending = ShotUploadStore.shared.active()
        ls119log("resume: \(pending.count) active record(s); liveTasks=\(live.count)")
        for rec in pending {
            ls119log("resume record id=\(rec.id) state=\(rec.state.rawValue) live=\(live.contains(rec.id))")
        }
        for rec in pending {
            switch rec.state {
            case .pending:
                // Resume is an explicit reconnect/foreground trigger → try now, bypassing the offline backoff
                // timer (the in-flight guard prevents a concurrent double-start).
                await startUpload(id: rec.id)
            case .uploading:
                // A live background task will deliver completion itself; if none survived, re-start (re-sign).
                if !live.contains(rec.id) { await startUpload(id: rec.id) }
            case .uploaded:
                // Upload done, analyze never started → run it (off the resume path, so others aren't blocked).
                let rid = rec.id
                Task { await self.runAnalyze(id: rid) }
            case .analyzing:
                // Analyze was in flight when we died. Don't blindly re-POST (would duplicate a shot the server
                // already started) — check whether the shot exists server-side first.
                let rid = rec.id
                Task { await self.recoverAnalyzing(id: rid) }
            case .done, .failed:
                break
            }
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

    /// DEC-119: the user explicitly cancelled the foreground shot's analysis cover — cancel the in-flight upload
    /// task and drop its durable record so it doesn't keep uploading in the background and deliver later.
    func cancelForegroundUpload() {
        guard let id = foregroundUploadId else { return }
        BackgroundUploadManager.shared.cancel(id: id)
        ShotUploadStore.shared.remove(id)
        inFlightUploads.remove(id)
        inFlightAnalyze.remove(id)
        foregroundUploadId = nil
        clearPendingAnalysis()
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
        shotCount = 0
        // DEC-119: persist the active-session mirror (shotCount 0) so the banner / resume prompt survive relaunch & offline.
        setActiveSession(id: session.id, mode: mode, startedAt: session.started_at ?? Date().timeIntervalSince1970)
        track("session_started")      // §2 (DEC-098 M3): explicit start from Setup
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

    /// Full session feedback (rating + tags + diagnostics), used by the session-end feedback sheet.
    func submitSessionFeedback(rating: Int, tags: [String], text: String, diagnostics: Bool) async throws {
        guard let sid = sessionId else { return }
        let client = try makeClient()
        try await client.feedbackFull(sessionId: sid, rating: rating, tags: tags,
                                      text: text.isEmpty ? nil : text, diagnostics: diagnostics,
                                      appPhase: appPhase)
    }

    /// DEC-123: records the F&F consent — stores the version + timestamp on the account (and the build's phase
    /// as the account cohort; the server forces owner/staged to dev) and marks it accepted on this device.
    func recordFFConsent() async {
        let now = ISO8601DateFormatter().string(from: Date())
        if let client = try? makeClient() {
            // Best-effort: never block entry on a profile write failing — the local flag still advances so the
            // tester isn't stuck behind the consent screen offline; the cohort re-syncs on the next profile save.
            try? await client.putProfile(["cohort": appPhase,
                                          "ff_consent_version": Self.ffConsentVersion,
                                          "ff_consent_at": now])
        }
        ffConsentAcceptedVersion = Self.ffConsentVersion
    }

    /// DEC-124: general feedback from the Home Feedback button → the one retained store (source='general').
    /// Category rides in tags[0]; app_phase + app_version always sent; device/iOS/screen/last-session go in
    /// diagnostics only when the tester leaves "Include diagnostics" on. Throws so the sheet can keep the
    /// typed text and let the user retry.
    func submitGeneralFeedback(category: String, text: String, includeDiagnostics: Bool,
                               currentScreen: String, screenshotJPEGBase64: String?) async throws {
        let client = try makeClient()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        var diagnostics: [String: Any]? = nil
        if includeDiagnostics {
            var d: [String: Any] = ["device_model": UIDevice.modelIdentifier,
                                    "ios_version": UIDevice.current.systemVersion,
                                    "current_screen": currentScreen]
            if let sid = activeSession?.id ?? sessionId { d["last_session_id"] = sid }
            if let shot = result?.shotId { d["last_shot_id"] = shot }
            if let shot = screenshotJPEGBase64 { d["screenshot_jpeg_b64"] = shot }
            diagnostics = d
        }
        try await client.submitGeneralFeedback(category: category, text: text, appPhase: appPhase,
                                               appVersion: appVersion, diagnostics: diagnostics)
    }

    /// Ends the active session; stores the returned summary for the summary screen.
    func endCurrentSession() async throws {
        guard let sid = sessionId else { return }
        let client = try makeClient()
        endSummary = try await client.endSession(sid)
        sessionId = nil
        // DEC-119: the user explicitly ended it → drop the active-session mirror (banner/prompt stop showing).
        activeSession = nil
        persistActiveSession()
    }

    /// Marks the bowler profile complete after the setup + add-ball steps → the app root switches to Home.
    func finishProfileSetup() {
        profileComplete = true
    }
}
