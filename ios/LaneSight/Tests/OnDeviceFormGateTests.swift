import XCTest
import Foundation
@testable import LaneSight

/// DEC-128 / DEC-121 on-device Form parity gate — the form analogue of `OnDeviceGateTests` (shots).
///
/// Runs the on-device MediaPipe Form engine (`OnDeviceFormEngine.analyze`) on the labeled form clips and checks:
///   1. **Determinism** — two runs on the same clip return byte-identical events + metrics (DEC-126 P0 rule).
///   2. **Engine parity vs the Python server reference** — each event the reference surfaces
///      (validation/form_ondevice_golden.json) is within ±2 frames on device, and step count matches the
///      reference exactly. This is "metrics within tolerance of the server's on the same clips" (DEC-128 §3).
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

    static let heldOut: Set<String> = ["IMG_8980"]
    static let gateFrames = 2.0
    // engine event key -> label key (matches form_baseline.EVENT_MAP); E2 is null in the reference (DEC-120).
    static let eventMap: [(String, KeyPath<LabelClip, Double?>, String, Bool)] = [
        ("E2", \.E2_ball_start_s, "ball start", true),
        ("E4", \.E4_backswing_top_s, "backswing top", true),
        ("E5", \.E5_slide_start_s, "slide start", false),
        ("E7", \.E7_release_s, "release", true),
        ("E8", \.E8_slide_stop_s, "slide stop", true),
    ]

    func testOnDeviceFormParityOnLabeledClips() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let labels = loadJSON(Labels.self, "form_labels", bundle),
              let golden = loadJSON(Golden.self, "form_ondevice_golden", bundle) else {
            throw XCTSkip("form_labels.json / form_ondevice_golden.json not bundled — add them as test resources.")
        }
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

            let t0 = Date()
            let a1 = try OnDeviceFormEngine.analyze(clipURL: url, handed: "right", bundle: bundle)
            let wall = Date().timeIntervalSince(t0)
            let a2 = try OnDeviceFormEngine.analyze(clipURL: url, handed: "right", bundle: bundle)

            // 1. determinism (hard) — identical located events + the headline metrics
            for k in ["E2", "E4", "E6", "E7", "E8"] {
                XCTAssertEqual(ev(a1, k), ev(a2, k), "non-deterministic event \(k) on \(clip)")
            }
            for k in ["swing_time", "backswing_time", "downswing_time", "step_count", "rhythm_ratio"] {
                XCTAssertEqual(a1.metrics[k]?.value, a2.metrics[k]?.value, "non-deterministic metric \(k) on \(clip)")
            }

            // 2. engine parity vs the server reference (golden) — NOT applied to the held-out clip.
            if let gevents = gold?.events, !heldOut {
                for key in ["E4", "E6", "E7", "E8"] {
                    guard let g = gevents[key] ?? nil, let d = ev(a1, key) else { continue }
                    let df = abs(d - g) * fps
                    XCTAssertLessThanOrEqual(df, Self.gateFrames,
                        "\(clip) \(key): on-device \(d)s vs server \(g)s = \(df) frames > ±\(Self.gateFrames) (engine parity)")
                }
                if let gsc = gold?.step_count?.value, let dsc = a1.metrics["step_count"]?.value {
                    XCTAssertEqual(dsc, gsc, "\(clip): on-device step_count \(dsc) != server \(gsc) (engine parity)")
                }
            }

            // 3 + 4. report ground-truth deltas + runtime (one grep-able JSON row per clip)
            var evRows: [String: Any] = [:]
            for (ekey, kp, _, dec118) in Self.eventMap {
                let det = ev(a1, ekey)
                let gt = lab?[keyPath: kp]
                var r: [String: Any] = ["dec118": dec118]
                r["det_s"] = det as Any
                r["label_s"] = gt as Any
                if let det, let gt { r["d_frames"] = (det - gt) * fps }
                evRows[ekey] = r
            }
            let row: [String: Any] = [
                "clip": clip, "held_out": heldOut, "view_label": lab?.view ?? "?",
                "view_detected": a1.view, "fps": fps, "wall_s": wall, "status": a1.status,
                "step_count": a1.metrics["step_count"]?.value as Any,
                "step_count_label": lab?.step_count as Any,
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
}
