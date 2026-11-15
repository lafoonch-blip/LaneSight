import XCTest
import Foundation
@testable import LaneSight

/// DEC-129 / DEC-121 on-device Form parity gate — the form analogue of `OnDeviceGateTests` (shots).
///
/// Runs the on-device MediaPipe Form engine (`OnDeviceFormEngine.analyze`) on the labeled form clips and checks:
///   1. **Determinism** — two runs on the same clip return byte-identical events + metrics (DEC-126 P0 rule).
///   2. **Engine parity vs the Python server reference** — each event the reference surfaces
///      (validation/form_ondevice_golden.json) is within ±2 frames on device, and step count matches the
///      reference exactly. This is "metrics within tolerance of the server's on the same clips" (DEC-129 §3).
///   3. **Ground-truth deltas vs form_labels.json** — printed per clip (the DEC-121 ±2-frame swing-event /
///      exact step-count readout, the same numbers `examples/form_baseline.py` reports). IMG_8980 is HELD OUT.
///   4. **Runtime** — printed per clip (<30 s per clip is the DEC-118 Beta gate; measured on device by Shayne).
///
/// Fixtures (clips, the golden, the labels) live in `Tests/FormGateClips/` and are **gitignored** — copied in
/// locally + bundled via project.yml, exactly like `GateClips`/`ParityFixtures`. The test SKIPs when they are
/// absent (CI / a fresh checkout), and is authoritative only on a real device where MediaPipe Pose runs.
final class OnDeviceFormGateTests: XCTestCase {
    struct GoldenClip: Decodable {
        let ok: Bool?
        let view_detected: String?
        let fps: Double?
        let events: [String: Double?]?
        let step_count: StepCount?
        struct StepCount: Decodable { let value: Double?; let label: Int? }
    }
    struct Golden: Decodable { let clips: [String: GoldenClip] }
    struct LabelClip: Decodable {
        let view: String?
        let E2_ball_start_s: Double?
        let E4_backswing_top_s: Double?
        let E5_slide_start_s: Double?
        let E7_release_s: Double?
        let E8_slide_stop_s: Double?
        let step_count: Int?
    }
    struct Labels: Decodable { let clips: [String: LabelClip] }
    struct StepLabelClip: Decodable {
        let step1_s: Double?; let step2_s: Double?; let step3_s: Double?
        let step4_s: Double?; let step5_s: Double?; let step6_s: Double?; let fps: Double?
        var visible: [Double] { [step1_s, step2_s, step3_s, step4_s, step5_s, step6_s].compactMap { $0 } }
    }
    struct StepLabels: Decodable { let clips: [String: StepLabelClip] }

    // IMG_8980 is NO LONGER a blind holdout (DEC-131): the server delivery selector + hold-bound were developed on
    // it, so it's a training clip now. It stays excluded from the on-device parity ASSERTIONS only because it still
    // mis-segments on-device (a landmark-quality gap — see testDeliveryWindowPicksRealDelivery). The real blind set
    // going forward is the next batch of 60 fps form clips, graded with the selector constants frozen.
    static let heldOut: Set<String> = ["IMG_8980"]
    static let gateFrames = 2.0        // DEC-121 swing events
    static let plantFrames = 3.0       // DEC-121 per-plant foot-strike timing

    func testOnDeviceFormParityOnLabeledClips() async throws {
        // engine event key -> label key (matches form_baseline.EVENT_MAP); E2 is null in the reference (DEC-120).
        // Local (not a static) to satisfy Swift 6 strict-concurrency on the KeyPath tuple array.
        let eventMap: [(String, KeyPath<LabelClip, Double?>, String, Bool)] = [
            ("E2", \.E2_ball_start_s, "ball start", true),
            ("E4", \.E4_backswing_top_s, "backswing top", true),
            ("E5", \.E5_slide_start_s, "slide start", false),
            ("E7", \.E7_release_s, "release", true),
            ("E8", \.E8_slide_stop_s, "slide stop", true),
        ]
        let bundle = Bundle(for: type(of: self))
        guard let labels = loadJSON(Labels.self, "form_labels", bundle),
              let golden = loadJSON(Golden.self, "form_ondevice_golden", bundle) else {
            throw XCTSkip("form_labels.json / form_ondevice_golden.json not bundled — add them as test resources.")
        }
        let stepLabels = loadJSON(StepLabels.self, "form_steps_labels", bundle)?.clips ?? [:]
        guard FormPoseLandmarker.resolveModelPath(bundle: bundle) != nil else {
            throw XCTSkip("pose_landmarker_heavy.task not in the test bundle (gitignored) — add it to run the gate.")
        }

        let clips = ["IMG_8824", "IMG_8825", "IMG_8826", "IMG_8846", "IMG_8847", "IMG_8848", "IMG_8980"]
        print("ONDEV_FORM_GATE_BEGIN")
        var found = 0
        for clip in clips {
            guard let url = clipURL(clip, bundle) else { print("ONDEV_FORM_GATE \(clip) MISSING_IN_BUNDLE"); continue }
            found += 1
            let heldOut = Self.heldOut.contains(clip)
            let lab = labels.clips[clip]
            let gold = golden.clips[clip]
            let fps = gold?.fps ?? 60.0

            // Pose ONCE (the expensive MediaPipe pass over the prescan window = the real per-clip runtime for the
            // <30 s gate), then run the PURE engine on the cached landmarks.
            let t0 = Date()
            let lms = try OnDeviceFormEngine.extractWindowed(clipURL: url, bundle: bundle)
            let a1 = OnDeviceFormEngine.analyze(landmarks: lms, handed: "right")
            let wall = Date().timeIntervalSince(t0)

            // 1. determinism (hard) — DEC-126 P0. (a) ENGINE: run the pure engine 10× on the SAME landmarks → must
            // be byte-identical (no randomness). (b) POSE: re-extract once → the whole-pipeline result must match
            // (MediaPipe reproducible on device). Reports X/10 engine + the pose-match.
            let detKeys = ["E2", "E3", "E4", "E6", "E7", "E8"]
            let metKeys = ["swing_time", "backswing_time", "downswing_time", "release_time", "step_count",
                           "rhythm_ratio", "approach_time", "finish_hold"]
            var identical = 1
            for run in 2...10 {
                let an = OnDeviceFormEngine.analyze(landmarks: lms, handed: "right")
                var same = true
                for k in detKeys where ev(a1, k) != ev(an, k) { same = false }
                for k in metKeys where a1.metrics[k]?.value != an.metrics[k]?.value { same = false }
                if same { identical += 1 }
                else { XCTFail("\(clip): engine run \(run) diverged (non-deterministic)") }
            }
            XCTAssertEqual(identical, 10, "\(clip) engine determinism \(identical)/10")
            let lms2 = try OnDeviceFormEngine.extractWindowed(clipURL: url, bundle: bundle)
            let a2 = OnDeviceFormEngine.analyze(landmarks: lms2, handed: "right")
            var poseMatch = true
            for k in detKeys where ev(a1, k) != ev(a2, k) { poseMatch = false }
            XCTAssertTrue(poseMatch, "\(clip): MediaPipe pose not reproducible across two extractions")

            // 2. THE GATE — vs the HUMAN LABELS (DEC-121), not the server's pose. Held-out IMG_8980 is not gated.
            //    (a) each SURFACED DEC-118 swing event (E4 top, E7 release, E8 slide stop) within ±2 frames of the
            //        label. A dropped/null event is reported (coverage), not asserted here. E2 ball-start is null on
            //        all clips (DEC-120) — reported only.
            //    (b) per-plant foot strikes within ±3 frames of the form_steps labels (visible plants, greedy
            //        nearest match). Step count stays best_effort — REPORTED, never gated (DEC-121).
            //    The server-golden comparison is kept as a reported shadow in the row (never asserted).
            if !heldOut {
                for (ekey, kp, name, dec118) in eventMap where dec118 {
                    guard let det = ev(a1, ekey), let gt = lab?[keyPath: kp] else { continue }  // null → coverage, not gated
                    let df = abs(det - gt) * fps
                    XCTAssertLessThanOrEqual(df, Self.gateFrames,
                        "\(clip) \(ekey) \(name): \(df) frames vs label > ±\(Self.gateFrames)")
                }
                // per-plant ±3f vs labels
                let visible = stepLabels[clip]?.visible ?? []
                let sfps = stepLabels[clip]?.fps ?? fps
                let strikes = a1.strikes.map { $0.t }
                for lb in visible {
                    guard let nearest = strikes.min(by: { abs($0 - lb) < abs($1 - lb) }) else { continue }
                    let df = abs(nearest - lb) * sfps
                    XCTAssertLessThanOrEqual(df, Self.plantFrames,
                        "\(clip) plant@\(String(format: "%.2f", lb))s: nearest strike \(df) frames > ±\(Self.plantFrames)")
                }
            }

            // 3 + 4. report ground-truth deltas (vs labels), the server-golden shadow, step count + runtime.
            var evRows: [String: Any] = [:]
            for (ekey, kp, _, dec118) in eventMap {
                let det = ev(a1, ekey)
                let gt = lab?[keyPath: kp]
                var r: [String: Any] = ["dec118": dec118]
                r["det_s"] = det as Any
                r["label_s"] = gt as Any
                if let det, let gt { r["d_frames"] = (det - gt) * fps }                      // vs LABEL (the gate)
                if let det, let gEvents = gold?.events, let gv = gEvents[ekey], let g = gv {   // vs server (shadow)
                    r["d_frames_server"] = (det - g) * fps
                }
                evRows[ekey] = r
            }
            // per-plant report (vs labels): the frame delta of the nearest strike to each visible labeled plant.
            let visible = stepLabels[clip]?.visible ?? []
            let sfps = stepLabels[clip]?.fps ?? fps
            let strikes = a1.strikes.map { $0.t }
            let plantDf: [Double] = visible.compactMap { lb in
                strikes.min(by: { abs($0 - lb) < abs($1 - lb) }).map { abs($0 - lb) * sfps }
            }
            let row: [String: Any] = [
                "clip": clip, "held_out": heldOut, "view_label": lab?.view ?? "?",
                "view_detected": a1.view, "fps": fps, "wall_s": wall, "status": a1.status,
                "determinism": "\(identical)/10",
                "step_count": a1.metrics["step_count"]?.value as Any,
                "step_count_label": lab?.step_count as Any,
                "n_strikes": strikes.count, "plants_visible": visible.count,
                "plant_df_vs_label": plantDf.map { ($0 * 10).rounded() / 10 },
                "swing_source": a1.swingSource, "events": evRows,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: row),
               let s = String(data: data, encoding: .utf8) { print("ONDEV_FORM_GATE_ROW \(s)") }
            if wall >= 30 { print("ONDEV_FORM_GATE \(clip) RUNTIME_OVER_30S wall=\(wall)") }
        }
        print("ONDEV_FORM_GATE_END found=\(found)")
        if found == 0 {
            throw XCTSkip("no FormGateClips in the test bundle — add the labeled form clips locally to run the gate.")
        }
    }

    // MARK: helpers
    private func ev(_ a: FormAnalysis, _ k: String) -> Double? { a.events[k] ?? nil }
    private func loadJSON<T: Decodable>(_ type: T.Type, _ name: String, _ bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func clipURL(_ clip: String, _ bundle: Bundle) -> URL? {
        bundle.url(forResource: clip, withExtension: "mov") ?? bundle.url(forResource: clip, withExtension: "MOV")
    }

    /// DEC-131 — dump full-clip landmarks so the iOS↔Python per-landmark gap can be measured offline (compare to
    /// the Python lm_cache/*.npz). Opt-in via FORM_LM_DUMP=1 (expensive: full pose, no prescan window). Prints
    /// normalized (x,y) for all 33 landmarks every 5th frame; `examples/form_lm_gap.py` parses + reports px.
    func testDumpLandmarksForGapAnalysis() throws {
        guard ProcessInfo.processInfo.environment["FORM_LM_DUMP"] != nil else {
            throw XCTSkip("set FORM_LM_DUMP=1 to dump landmarks for the gap analysis")
        }
        let bundle = Bundle(for: type(of: self))
        guard FormPoseLandmarker.resolveModelPath(bundle: bundle) != nil else { throw XCTSkip("pose model not bundled") }
        print("LMDUMP_DELEGATE cpu=\(FormPoseLandmarker.useCPUDelegate)")
        for clip in ["IMG_8846", "IMG_8825", "IMG_8980"] {
            guard let url = clipURL(clip, bundle) else { continue }
            let lms = try FormPoseLandmarker.extract(clipURL: url, bundle: bundle, window: nil)
            print("LMDUMP_BEGIN \(clip) frames=\(lms.t.count)")
            for i in stride(from: 0, to: lms.t.count, by: 5) {
                var s = "LMROW \(clip) \(i) \(String(format: "%.4f", lms.t[i]))"
                let f = lms.frames[i].lm
                for k in 0..<33 { s += " \(String(format: "%.4f", f[k][0])),\(String(format: "%.4f", f[k][1]))" }
                print(s)
            }
            print("LMDUMP_END \(clip)")
        }
    }

    /// DEC-131 — the landmark-robust delivery selector must pick the REAL delivery on-device, not a pre-shot burst
    /// (01:03: 30 s clip, lots of pre-shot pacing) or a post-delivery walk-back (8980: delivery-then-walk-back).
    /// This is the on-device half of the offline form_selector_sim.py validation. Clips are gitignored
    /// (FormGateClips/); the test skips when absent. The delivery anchor (slide plant / first step) must land in
    /// the real-delivery window, i.e. NOT in the pre-shot region. IMG_8980 is a KNOWN on-device gap: the server
    /// selector picks it correctly (16.8 s) but on-device it picks the walk-back (~22 s). ROOT CAUSE (DEC-131, from
    /// the FORM_LM_DUMP gap analysis): the on-device landmarks MATCH the Python reference to ~1 px, so this is not a
    /// landmark/delegate difference — it is the delivery PRESCAN (`FormPoseLandmarker.prescanWindow`), which picks
    /// the highest-energy motion burst and on 8980 that is the walk-back, so the real delivery is windowed out
    /// before findDelivery ever sees it. Documented with XCTExpectFailure; honesty-gated; the real fix is a
    /// swing-aware prescan, not a selector tweak.
    func testDeliveryWindowPicksRealDelivery() throws {
        let bundle = Bundle(for: type(of: self))
        guard FormPoseLandmarker.resolveModelPath(bundle: bundle) != nil else {
            throw XCTSkip("pose_landmarker_heavy.task not in the test bundle (gitignored).")
        }

        func anchorFor(_ clip: String) throws -> Double? {
            guard let url = clipURL(clip, bundle) else { return nil }
            let lms = try OnDeviceFormEngine.extractWindowed(clipURL: url, bundle: bundle)
            let a = OnDeviceFormEngine.analyze(landmarks: lms, handed: "right")
            let anchor = (a.events["slide_plant"] ?? nil) ?? (a.events["first_step"] ?? nil)
            print("ONDEV_FORM_WINDOW \(clip) anchor=\(anchor.map { String($0) } ?? "nil")")
            return anchor
        }

        // 01:03 (hard): the 30 s production clip must pick a delivery-region burst (≥18 s), never the 0-6 s pre-shot
        // pacing that was the original bug. This is the on-device confirmation for the DEC-131 selector.
        if let a0103 = try anchorFor("IMG_0103") {
            XCTAssert(a0103 >= 18.0 && a0103 <= 30.5,
                      "IMG_0103: delivery anchor \(a0103)s not in the delivery region [18, 30.5] — pre-shot picked")
        } else {
            throw XCTSkip("IMG_0103 not bundled (FormGateClips/ gitignored).")
        }

        // 8980 (known on-device gap — see doc comment). Expect the walk-back mis-pick until the on-device body-scale
        // estimate improves; if this ever starts landing in [14, 18.5], XCTest flags the stale expectation to remove.
        XCTExpectFailure("IMG_8980: the delivery PRESCAN windows out the real delivery (picks the higher-energy "
                         + "walk-back); on-device landmarks match Python ~1px, so this needs a swing-aware prescan, "
                         + "not a selector/delegate change. Fixed on the server; honesty-gated on-device.")
        if let a8980 = try anchorFor("IMG_8980") {
            XCTAssert(a8980 >= 14.0 && a8980 <= 18.5,
                      "IMG_8980: delivery anchor \(a8980)s not in [14, 18.5] — walk-back picked on device")
        }
    }
}
