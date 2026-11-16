import XCTest
@testable import LaneSight

/// DEC-119 session-durability unit tests: the pure, headless-testable pieces of the persist-before-upload +
/// background-upload + resume design. The device lifecycle (kill/crash/airplane-mode/30-min background) is
/// exercised on-device per the checklist — not here.
final class SessionDurabilityTests: XCTestCase {

    // MARK: resume-prompt decision (DEC-119)

    func testColdLaunchPromptsWhenActiveSession() {
        XCTAssertTrue(AppModel.shouldPromptResume(coldLaunch: true, backgroundedAt: nil, now: 1000, hasActiveSession: true))
    }

    func testColdLaunchNoPromptWithoutActiveSession() {
        XCTAssertFalse(AppModel.shouldPromptResume(coldLaunch: true, backgroundedAt: nil, now: 1000, hasActiveSession: false))
    }

    func testWarmForegroundUnder30MinNoPrompt() {
        let now = 10_000.0
        let bg = now - (29 * 60)   // 29 min < threshold
        XCTAssertFalse(AppModel.shouldPromptResume(coldLaunch: false, backgroundedAt: bg, now: now, hasActiveSession: true))
    }

    func testWarmForegroundAtLeast30MinPrompts() {
        let now = 10_000.0
        let bg = now - (30 * 60)   // exactly 30 min → prompt
        XCTAssertTrue(AppModel.shouldPromptResume(coldLaunch: false, backgroundedAt: bg, now: now, hasActiveSession: true))
    }

    func testWarmForegroundNoBackgroundStampNoPrompt() {
        XCTAssertFalse(AppModel.shouldPromptResume(coldLaunch: false, backgroundedAt: 0, now: 10_000, hasActiveSession: true))
    }

    // MARK: upload backoff

    func testBackoffIsMonotonicAndCapped() {
        let d1 = UploadBackoff.delay(attempt: 1)
        let d2 = UploadBackoff.delay(attempt: 2)
        let d3 = UploadBackoff.delay(attempt: 3)
        XCTAssertEqual(d1, 2, accuracy: 0.001)
        XCTAssertEqual(d2, 4, accuracy: 0.001)
        XCTAssertEqual(d3, 8, accuracy: 0.001)
        XCTAssertLessThan(d1, d2)
        XCTAssertLessThan(d2, d3)
        XCTAssertLessThanOrEqual(UploadBackoff.delay(attempt: 20), 60)   // capped
        XCTAssertGreaterThanOrEqual(UploadBackoff.maxAttempts, 1)
    }

    // MARK: durable record round-trip + state

    func testShotUploadCodableRoundTrip() throws {
        let rec = ShotUpload(id: "abc", sessionId: "sess-1", source: "live", captureMode: "shot",
                             createdAt: 123.0, clipPath: "/tmp/clip.mov", state: .uploading,
                             storagePath: "p/obj.mov", uploadURL: "https://x/y", metadataJSON: "{\"a\":1}",
                             clientTimingsJSON: "{\"trim_s\":1.2}", attempts: 1, nextAttemptAt: 0, lastError: nil)
        let data = try JSONEncoder().encode(rec)
        let back = try JSONDecoder().decode(ShotUpload.self, from: data)
        XCTAssertEqual(rec, back)
    }

    func testTerminalFlag() {
        func make(_ s: ShotUpload.State) -> ShotUpload {
            ShotUpload(id: "x", sessionId: nil, source: "upload", captureMode: "shot", createdAt: 0,
                       clipPath: "/tmp/c.mov", state: s, storagePath: nil, uploadURL: nil,
                       metadataJSON: "{}", clientTimingsJSON: nil, attempts: 0, nextAttemptAt: 0, lastError: nil)
        }
        XCTAssertTrue(make(.done).isTerminal)
        XCTAssertTrue(make(.failed).isTerminal)
        XCTAssertFalse(make(.pending).isTerminal)
        XCTAssertFalse(make(.uploading).isTerminal)
        XCTAssertFalse(make(.uploaded).isTerminal)
        XCTAssertFalse(make(.analyzing).isTerminal)
    }

    @MainActor
    func testStoreSaveLoadActiveRemove() throws {
        let store = ShotUploadStore.shared
        let id = "test-\(UUID().uuidString)"
        let rec = ShotUpload(id: id, sessionId: "s", source: "live", captureMode: "shot",
                             createdAt: 1.0, clipPath: "/tmp/\(id).mov", state: .pending,
                             storagePath: nil, uploadURL: nil, metadataJSON: "{}", clientTimingsJSON: nil,
                             attempts: 0, nextAttemptAt: 0, lastError: nil)
        store.save(rec)
        defer { store.remove(id) }

        let loaded = store.load(id)
        XCTAssertEqual(loaded?.id, id)
        XCTAssertEqual(loaded?.state, .pending)
        XCTAssertTrue(store.active().contains { $0.id == id })

        // A terminal record is excluded from active().
        var done = rec; done.state = .done
        store.save(done)
        XCTAssertFalse(store.active().contains { $0.id == id })

        store.remove(id)
        XCTAssertNil(store.load(id))
    }

    @MainActor
    func testDurableClipURLIsStableAndNotTemp() {
        let url = ShotUploadStore.shared.durableClipURL(for: "clip-id", ext: "mov")
        XCTAssertEqual(url.lastPathComponent, "clip-id.mov")
        XCTAssertFalse(url.path.contains("/tmp/"), "durable clips must not live in the OS-purgeable tmp dir")
        XCTAssertTrue(url.path.contains("LaneSightUploads"))
    }

    // MARK: outcome classification feeds retry vs. fail correctly (shape check)

    func testUploadOutcomeEquatable() {
        XCTAssertEqual(UploadOutcome.success(status: 200), UploadOutcome.success(status: 200))
        XCTAssertNotEqual(UploadOutcome.success(status: 200), UploadOutcome.transientFailure("x"))
    }
}
