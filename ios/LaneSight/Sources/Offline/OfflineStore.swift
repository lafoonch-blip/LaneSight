import Foundation
import Network
import Combine

// OD-02 (DEC-102/103): offline-first local store + outbox. FIRST INCREMENT.
// Durable, account-scoped, encrypted-at-rest JSON records under Application Support. Dependency-free and
// free of SwiftData/Swift-6 ModelContext concurrency surprises for an append-mostly outbox (the spec's
// "cache + outbox"; SwiftData/GRDB stay the option if rich querying is later needed).
//
// NOT yet wired into AppModel.runPipeline — that wiring + the on-device airplane-mode acceptance run
// (which needs physical network toggling) is the next step, gated on Shayne's verification. The server
// stays the source of truth; nothing here is authoritative and no metric is ever computed locally.

// MARK: records

/// A shot captured while offline (or whose analyze request hasn't confirmed yet). Immutable result once set.
struct PendingShot: Codable, Identifiable, Equatable {
    let id: String                 // client UUID
    let accountRef: String
    let sessionId: String?
    let capturedAt: Date
    let source: String             // "live" | "upload"
    let captureMode: String        // "shot" | "form"
    var localClipPath: String?     // file URL path of the retained clip, if kept
    var state: String              // pending | analyzing | analyzed | failed
    var serverShotId: String?
    var engineVersion: String?
    let idempotencyKey: String
    var rev: Int = 0
}

/// One queued server action. Survives app kill (on disk). Drained by SyncEngine with backoff.
struct OutboxItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case analyze, sessionCreate, sessionEnd, profile, arsenal }
    let id: String
    let accountRef: String
    let kind: Kind
    let payloadJSON: Data
    let idempotencyKey: String
    let createdAt: Date
    var attempts: Int = 0
    var nextAttemptAt: Date
    var state: String = "pending"  // pending | inflight | done | dead
    var lastError: String?
}

// MARK: store

/// Account-scoped, file-protected persistence for the offline cache + outbox.
@MainActor
final class OfflineStore {
    static let shared = OfflineStore()
    private let fm = FileManager.default

    private var root: URL {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("LaneSightOffline", isDirectory: true)
    }
    private func dir(_ account: String, _ kind: String) -> URL {
        root.appendingPathComponent(account, isDirectory: true).appendingPathComponent(kind, isDirectory: true)
    }

    private func ensure(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        // Encrypt at rest: file is unreadable while the device is locked (§6.6 minimum).
        try? (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.iso.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    private func readAll<T: Decodable>(_ dirURL: URL, _ type: T.Type) -> [T] {
        guard let items = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "json" }.compactMap { u in
            (try? Data(contentsOf: u)).flatMap { try? JSONDecoder.iso.decode(T.self, from: $0) }
        }
    }

    // Shots
    func saveShot(_ s: PendingShot) throws {
        let d = dir(s.accountRef, "shots"); try ensure(d)
        try write(s, to: d.appendingPathComponent("\(s.id).json"))
    }
    func pendingShots(account: String) -> [PendingShot] {
        readAll(dir(account, "shots"), PendingShot.self)
            .filter { $0.state == "pending" || $0.state == "analyzing" }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    // Outbox
    func enqueue(_ item: OutboxItem) throws {
        let d = dir(item.accountRef, "outbox"); try ensure(d)
        try write(item, to: d.appendingPathComponent("\(item.id).json"))
    }
    func outbox(account: String) -> [OutboxItem] {
        readAll(dir(account, "outbox"), OutboxItem.self)
            .filter { $0.state == "pending" || $0.state == "inflight" }
            .sorted { $0.createdAt < $1.createdAt }
    }
    func update(_ item: OutboxItem) throws {
        let d = dir(item.accountRef, "outbox"); try ensure(d)
        try write(item, to: d.appendingPathComponent("\(item.id).json"))
    }

    /// Wipe everything for one account (sign-out / delete — §6.6).
    func purge(account: String) {
        try? fm.removeItem(at: root.appendingPathComponent(account, isDirectory: true))
    }

    /// New idempotency key = client UUID; stable per logical action so a retry never double-counts.
    static func newKey() -> String { UUID().uuidString }
}

// MARK: connectivity

/// Non-blocking connectivity signal (NWPathMonitor). Never gates navigation — drives banners + sync wake.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private let q = DispatchQueue(label: "ls.connectivity")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.isOnline = up }
        }
        monitor.start(queue: q)
    }
}

// MARK: sync

/// Drains the outbox when online and on foreground. Decoupled from APIClient via an injected sender so this
/// compiles and unit-tests headlessly; AppModel supplies the real sender when wiring is turned on.
@MainActor
final class SyncEngine {
    typealias Sender = (OutboxItem) async throws -> String   // returns the server id; throws → retry/backoff
    private let store: OfflineStore
    private let sender: Sender
    private var draining = false
    private let maxBackoff: TimeInterval = 300

    init(store: OfflineStore = .shared, sender: @escaping Sender) {
        self.store = store; self.sender = sender
    }

    /// Best-effort drain for one account. No duplicates: the server dedupes on the item's idempotency key.
    func drain(account: String, now: Date) async {
        guard !draining else { return }
        draining = true; defer { draining = false }
        for var item in store.outbox(account: account) where item.nextAttemptAt <= now {
            item.state = "inflight"; try? store.update(item)
            do {
                _ = try await sender(item)
                item.state = "done"; try? store.update(item)
            } catch {
                item.attempts += 1
                item.lastError = String(describing: error).prefix(200).description
                // Exponential backoff, capped. 4xx (non-retryable) is the sender's job to signal as `.dead`.
                let delay = min(maxBackoff, pow(2.0, Double(min(item.attempts, 8))))
                item.nextAttemptAt = now.addingTimeInterval(delay)
                item.state = "pending"
                try? store.update(item)
            }
        }
    }
}

// MARK: helpers

extension JSONEncoder {
    static let iso: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
extension JSONDecoder {
    static let iso: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
