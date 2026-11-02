import Foundation

// DEC-119: session durability + upload reliability.
//
// Three durable pieces survive relaunch / force-quit / crash / dead battery:
//   1. PersistedSession   — the one active session (server `sessions.ended_at` null), mirrored to disk so the
//      banner + resume prompt work offline and across a cold launch.
//   2. ShotUpload         — a per-shot record written the MOMENT recording finishes, BEFORE any upload, with
//      the clip kept in a durable dir (not tmp/, which the OS purges) until the shot reaches a terminal state.
//   3. BackgroundUploadManager — a background `URLSession` that PUTs the clip to Storage so the upload survives
//      app suspension (the exact silent-failure class DEC-119 removes: clip written, upload never started).
//
// The server stays the source of truth (durable jobs, DEC-110). Nothing here computes a metric; this is only
// the local mirror + the resilient transport.

// MARK: - Active session mirror

/// The one active session, mirrored from the server (`ended_at` null) and persisted locally. `shotCount` is a
/// best-effort local count for the banner / resume-prompt copy; the Active Session screen always re-reads the
/// authoritative shot list from the server.
nonisolated struct PersistedSession: Codable, Equatable {
    let id: String
    let mode: String          // "shot" | "form"
    let startedAt: Double     // epoch seconds
    var shotCount: Int
}

// MARK: - Durable per-shot upload record

/// A single shot's clip captured and queued for upload → analyze, persisted to disk before the upload starts.
nonisolated struct ShotUpload: Codable, Identifiable, Equatable {
    enum State: String, Codable {
        case pending        // persisted; PUT not started (or waiting on a backoff before the next attempt)
        case uploading      // PUT to Storage in flight on the background URLSession
        case uploaded       // PUT done (2xx); storage path known; analyze not yet confirmed
        case analyzing      // analyze request sent — the result is durable server-side even if the app dies
        case done           // delivered in-app
        case failed         // terminal failure (surfaced to the user with Retry)
    }
    let id: String                 // client UUID; also the background task's `taskDescription`
    var sessionId: String?         // nil → standalone upload (DEC-055); set when a live session is created lazily
    let source: String             // "live" | "upload"
    let captureMode: String        // "shot" | "form"
    let createdAt: Double
    var clipPath: String           // durable file path of the clip to upload
    var state: State
    var storagePath: String?       // Supabase Storage object path paired with `uploadURL` (re-signed per attempt)
    var uploadURL: String?         // signed PUT URL (short-lived; AppModel re-signs before each (re)start)
    var metadataJSON: String       // exact ShotMetadata.jsonString() captured at record time (ball/oil/target locked)
    var clientTimingsJSON: String? // phone-side stage timings captured pre-upload (DEC-092), carried onto analyze
    var attempts: Int              // upload attempts (drives backoff + give-up)
    var nextAttemptAt: Double      // epoch seconds; a `pending` record isn't (re)started before this
    var lastError: String?

    var isTerminal: Bool { state == .done || state == .failed }
    var clipURL: URL { URL(fileURLWithPath: clipPath) }
}

/// Durable, on-disk store for `ShotUpload` records + their clips. Lives in Application Support (survives
/// relaunch; not purged like tmp/). Account scoping isn't needed here: sign-out purges everything (§privacy).
@MainActor
final class ShotUploadStore {
    static let shared = ShotUploadStore()
    private let fm = FileManager.default

    private var baseDir: URL {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("LaneSightUploads", isDirectory: true)
    }
    private var clipsDir: URL { baseDir.appendingPathComponent("clips", isDirectory: true) }
    private var recordsDir: URL { baseDir.appendingPathComponent("records", isDirectory: true) }

    private func ensure(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A durable destination for a clip about to be queued. The caller copies/moves the recording here BEFORE
    /// starting the upload, so a kill between record-finish and upload-start can't strand the clip in tmp/.
    func durableClipURL(for id: String, ext: String) -> URL {
        ensure(clipsDir)
        return clipsDir.appendingPathComponent("\(id).\(ext.isEmpty ? "mov" : ext)")
    }

    // Records store epoch Doubles (not Date), so a plain coder is correct and keeps this file self-contained.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(_ rec: ShotUpload) {
        ensure(recordsDir)
        guard let data = try? encoder.encode(rec) else { return }
        let opts: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]
        try? data.write(to: recordsDir.appendingPathComponent("\(rec.id).json"), options: opts)
    }

    func load(_ id: String) -> ShotUpload? {
        let url = recordsDir.appendingPathComponent("\(id).json")
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ShotUpload.self, from: $0) }
    }

    func all() -> [ShotUpload] {
        guard let items = try? fm.contentsOfDirectory(at: recordsDir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { d in try? decoder.decode(ShotUpload.self, from: d) } }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Non-terminal records (pending / uploading / uploaded / analyzing) that still need work on relaunch.
    func active() -> [ShotUpload] { all().filter { !$0.isTerminal } }

    /// Removes a record and its clip. Call when a shot reaches a terminal, delivered state.
    func remove(_ id: String) {
        if let rec = load(id) { try? fm.removeItem(at: rec.clipURL) }
        try? fm.removeItem(at: recordsDir.appendingPathComponent("\(id).json"))
    }

    /// Wipe everything (sign-out / delete account).
    func purgeAll() {
        try? fm.removeItem(at: baseDir)
    }
}

// MARK: - Background upload transport

/// Outcome of one background PUT, classified for AppModel's retry/report logic.
nonisolated enum UploadOutcome: Equatable {
    case success(status: Int)
    case transientFailure(String)   // worth an automatic retry (5xx / 408 / 429 / transport / HTML error page)
    case permanentFailure(String)   // 4xx (bad/expired URL, auth) — surface + Retry, don't hammer
}

@MainActor
protocol BackgroundUploadObserver: AnyObject {
    func uploadProgress(id: String, fraction: Double)
    func uploadFinished(id: String, outcome: UploadOutcome)
}

/// Owns a process-wide background `URLSession` that survives app suspension and relaunches the app to deliver
/// transfer completion. It drives ONLY the clip PUT to Storage; AppModel owns signing, the analyze step, retry
/// scheduling and client-failure reporting. Delegate callbacks arrive on URLSession's own queue (nonisolated)
/// and hop to the main actor to touch the store / notify the observer.
@MainActor
final class BackgroundUploadManager: NSObject {
    static let shared = BackgroundUploadManager()
    static let sessionIdentifier = "com.lanesight.upload.bg"

    weak var observer: BackgroundUploadObserver?
    /// Set by the AppDelegate's handleEventsForBackgroundURLSession; called once the session finishes delivering
    /// events after a background relaunch so the system can snapshot the UI and re-suspend.
    var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        cfg.isDiscretionary = false                 // DEC-119: upload now, don't let the OS defer it
        cfg.sessionSendsLaunchEvents = true          // relaunch the app in the background on completion
        cfg.timeoutIntervalForRequest = 90           // per-request stall timeout
        cfg.timeoutIntervalForResource = 600         // whole-transfer timeout (large clip, slow center Wi-Fi)
        cfg.allowsCellularAccess = true
        cfg.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    /// Start (or restart) the PUT for a record whose `uploadURL` + `storagePath` are freshly signed. The clip is
    /// read from its durable file by the OS, so the transfer continues even after the app is suspended/killed.
    func start(_ rec: ShotUpload) {
        guard let urlString = rec.uploadURL, let url = URL(string: urlString) else {
            observer?.uploadFinished(id: rec.id, outcome: .permanentFailure("Missing upload URL"))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        let task = session.uploadTask(with: req, fromFile: rec.clipURL)
        task.taskDescription = rec.id
        task.resume()
    }

    /// Reconnect to in-flight transfers after (re)launch. Returns the set of record ids that still have a live
    /// task in the background session, so AppModel can (re)start the rest and leave these alone.
    func liveTaskIDs() async -> Set<String> {
        await withCheckedContinuation { cont in
            session.getAllTasks { tasks in
                let ids = tasks.compactMap { t -> String? in
                    (t.state == .running || t.state == .suspended) ? t.taskDescription : nil
                }
                cont.resume(returning: Set(ids))
            }
        }
    }

    /// Cancel a specific in-flight task (e.g. the user ended the session / explicitly cancelled).
    func cancel(id: String) {
        session.getAllTasks { tasks in
            for t in tasks where t.taskDescription == id { t.cancel() }
        }
    }

    private func classify(status: Int?, error: Error?, body: String) -> UploadOutcome {
        if let error {
            // NSURLErrorCancelled (-999) is a deliberate cancel — treat as transient (don't report a failure).
            return .transientFailure(error.localizedDescription)
        }
        guard let status else { return .transientFailure("No response") }
        if (200...299).contains(status) { return .success(status: status) }
        if status >= 500 || status == 408 || status == 429
            || body.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
            return .transientFailure("HTTP \(status)")
        }
        return .permanentFailure("HTTP \(status)")
    }
}

extension BackgroundUploadManager: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didSendBodyData bytesSent: Int64,
                                totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, let id = task.taskDescription else { return }
        let frac = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor [weak self] in self?.observer?.uploadProgress(id: id, fraction: frac) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        // Capture whether this was an explicit cancel so a user-cancelled upload isn't reported as a failure.
        let nsErr = error as NSError?
        let cancelled = nsErr?.domain == NSURLErrorDomain && nsErr?.code == NSURLErrorCancelled
        Task { @MainActor [weak self] in
            guard let self else { return }
            if cancelled { return }
            let outcome = self.classify(status: status, error: error, body: "")
            self.observer?.uploadFinished(id: id, outcome: outcome)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            let handler = self?.backgroundCompletionHandler
            self?.backgroundCompletionHandler = nil
            handler?()
        }
    }
}

// MARK: - Backoff

nonisolated enum UploadBackoff {
    /// Exponential backoff for upload retries, capped. attempt 1 → 2s, 2 → 4s, 3 → 8s … capped at 60s.
    static func delay(attempt: Int) -> TimeInterval {
        min(60, pow(2.0, Double(max(1, attempt))))
    }
    static let maxAttempts = 5
}
