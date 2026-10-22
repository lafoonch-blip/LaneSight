import Foundation
import SwiftUI
import Combine

/// Progress of the capture -> upload -> analyze -> result pipeline.
enum PipelineState: Equatable {
    case idle
    case creatingSession
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

    static func == (lhs: ShotResult, rhs: ShotResult) -> Bool {
        lhs.shotId == rhs.shotId && lhs.metrics.map(\.0) == rhs.metrics.map(\.0)
    }
}

@MainActor
final class AppModel: ObservableObject {
    // Persisted settings
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Keys.baseURL) } }
    @Published var devUser: String { didSet { defaults.set(devUser, forKey: Keys.devUser) } }
    @Published var handed: String { didSet { defaults.set(handed, forKey: Keys.handed) } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: Keys.onboarded) } }
    @Published var speedUnit: String { didSet { defaults.set(speedUnit, forKey: Keys.speedUnit) } }   // "mph" | "kmh"
    @Published var speakAdjustments: Bool { didSet { defaults.set(speakAdjustments, forKey: Keys.speak) } }

    // Capture / session options
    @Published var captureMode: String = "shot"   // "shot" | "form"
    @Published var arrowsBoardText: String = ""
    @Published var breakpointBoardText: String = ""
    @Published var feetBoardText: String = ""
    @Published var laneText: String = ""
    @Published var selectedOilPatternName: String?
    @Published var selectedOilPatternId: String?
    @Published var currentBallName: String?
    @Published var shotCount: Int = 0

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
        static let handed = "ls.handed"
        static let onboarded = "ls.onboarded"
        static let speedUnit = "ls.speedUnit"
        static let speak = "ls.speakAdjustments"
    }

    init() {
        // Default to this Mac's tailnet API (dev build). Edit in Settings; HTTP over the tailnet (see TEST_ON_PHONE.md).
        apiBaseURL = defaults.string(forKey: Keys.baseURL) ?? "http://shaynes-macbook-pro.tail7fa640.ts.net:8787"
        devUser = defaults.string(forKey: Keys.devUser) ?? "dev-shayne"
        handed = defaults.string(forKey: Keys.handed) ?? "R"
        onboarded = defaults.bool(forKey: Keys.onboarded)
        speedUnit = defaults.string(forKey: Keys.speedUnit) ?? "mph"
        speakAdjustments = defaults.bool(forKey: Keys.speak)
    }

    func makeClient() throws -> APIClient {
        try APIClient(baseURLString: apiBaseURL, devUser: devUser)
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
        do {
            let client = try makeClient()

            // 1. Ensure a session exists for this app run.
            let sid: String
            if let existing = sessionId {
                sid = existing
            } else {
                pipeline = .creatingSession
                sid = try await client.createSession(mode: "practice").id
                sessionId = sid
            }

            // 2. Upload the clip (multipart) with progress.
            pipeline = .uploading(0)
            let metadata = ShotMetadata(
                handed: handed,
                captureMode: captureMode,
                source: "live",
                intent: ShotIntent(feetBoard: Double(feetBoardText.trimmingCharacters(in: .whitespaces)),
                                   arrowsBoard: Double(arrowsBoardText.trimmingCharacters(in: .whitespaces)),
                                   breakpointBoard: Double(breakpointBoardText.trimmingCharacters(in: .whitespaces)))
            )
            let created = try await client.uploadShot(sessionId: sid, fileURL: fileURL, metadata: metadata) { [weak self] frac in
                self?.pipeline = .uploading(frac)
            }

            // 3. Poll the analysis job until done/failed.
            var last = JobResponse(id: created.job_id, kind: nil, state: "queued", reason: nil, timings: nil)
            pipeline = .analyzing(state: last.state, timings: [:])
            while true {
                last = try await client.job(created.job_id)
                pipeline = .analyzing(state: last.state, timings: last.timings ?? [:])
                if last.state == "done" { break }
                if last.state == "failed" {
                    pipeline = .failed("Analysis failed: \(last.reason ?? "unknown reason")")
                    return
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            // 4. Fetch the shot record + score.
            pipeline = .fetching
            let shot = try await client.shot(created.shot_id)
            let score = try await client.score()
            let metrics = MetricDisplay.ordered(shot.record?.metrics ?? [:])
            result = ShotResult(shotId: created.shot_id, metrics: metrics, score: score)
            shotCount += 1
            pipeline = .done
            showResult = true

            // Clean up the temp clip.
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            pipeline = .failed(error.localizedDescription)
        }
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

    /// Dev-stub "create account": set the dev user id, mark onboarded. No real Supabase auth in this slice.
    func completeOnboarding(devUserId: String) {
        let trimmed = devUserId.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { devUser = trimmed }
        onboarded = true
    }
}
