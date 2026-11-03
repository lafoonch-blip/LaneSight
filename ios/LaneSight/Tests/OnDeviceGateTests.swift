import XCTest
@testable import LaneSight

// DEC-117/DEC-128 device gate. Runs EVERY clip in the test bundle's GateClips/ folder through the NATIVE
// on-device engine ON THE PHONE and prints, per clip, the full structured metrics (value + status + reason_code),
// the per-stage report, device cost, and diag. Parsed offline by ops/parity_report.py and compared against the
// server outcome rows for the same clip (DEC-128 item 3 parity). Clips live in GateClips/ (added locally via
// project.yml; gitignored, not committed — like the server regression tier, the test SKIPS if the folder is empty).
//
// Run on device:
//   xcodebuild test -scheme LaneSight -destination 'id=<device-udid>' \
//     -only-testing:LaneSightTests/OnDeviceGateTests
final class OnDeviceGateTests: XCTestCase {
    func testOnDeviceSpeedAndRevOnLabeledClips() async throws {
        // Labeled truth (foul→pins average from Shayne's labels) for the IMG_* validation clips; retained/upload
        // clips have no truth and just report their measured values for the parity diff.
        let truth: [String: Double] = [
            "IMG_8751": 17.872, "IMG_8752": 18.003, "IMG_8753": 18.275, "IMG_8754": 17.362,
            "IMG_8963": 17.74, "IMG_8964": 16.879, "IMG_8965": 17.49, "IMG_8966": 17.24, "IMG_8967": 17.12,
            "IMG_8968": 17.00, "IMG_8969": 18.139, "IMG_8970": 17.24, "IMG_8971": 17.48, "IMG_8972": 17.00,
            "IMG_8973": 17.74, "IMG_8974": 17.36, "IMG_8975": 18.00, "IMG_8976": 17.10, "IMG_8977": 16.88,
            "IMG_8978": 17.12, "IMG_8979": 17.74, "IMG_8981": 18.413,
        ]
        let bundle = Bundle(for: type(of: self))
        // Enumerate ALL clips in GateClips/ (any name), both .mov and .MOV, so retained/upload clips dropped in
        // the folder are picked up without editing this list.
        var urls: [URL] = []
        for ext in ["mov", "MOV"] {
            urls += bundle.urls(forResourcesWithExtension: ext, subdirectory: "GateClips") ?? []
            urls += bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        // de-dup by last path component, stable order
        var seen = Set<String>(); var clips: [URL] = []
        for u in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if seen.insert(u.lastPathComponent).inserted { clips.append(u) }
        }
        // Optional allowlist (comma-separated clip base names, no extension) so a focused parity run can target a
        // few clips without re-bundling. Pass via `env TEST_RUNNER_LS_GATE_CLIPS=80ae104f,7936cc3f xcodebuild test`.
        if let allow = ProcessInfo.processInfo.environment["LS_GATE_CLIPS"], !allow.isEmpty {
            let want = Set(allow.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            clips = clips.filter { want.contains($0.deletingPathExtension().lastPathComponent) }
        }
        print("ONDEV_GATE_BEGIN")
        var found = 0
        for url in clips {
            let name = url.deletingPathExtension().lastPathComponent
            found += 1
            // Faithful to the live on-device-first path: trim to the 5 s shot window (measureOnDevicePrimary does
            // the same) before running the engine, so the gate reproduces what the user sees — and runs fast.
            // LS_GATE_NOTRIM=1 runs the FULL clip (diagnostic: isolate the trim from the detector).
            let noTrim = (ProcessInfo.processInfo.environment["LS_GATE_NOTRIM"] == "1")
            let trimmed = noTrim ? url : await VideoTrimmer.trimToShotWindow(url, tail: 5.0)
            defer { if trimmed != url { try? FileManager.default.removeItem(at: trimmed) } }
            let body = await OnDeviceShadow.run(clipURL: trimmed, shotId: "gate-\(name)", source: "upload",
                                                sessionId: nil, captureMode: "shot", appVersion: "gate")
            let metrics = body["metrics"] as? [String: Any] ?? [:]
            let perf = body["device_perf"] as? [String: Any] ?? [:]
            let f2p = metrics["speed_avg_foul_to_pins"] as? Double
            let err: Double? = (truth[name] != nil && f2p != nil) ? (f2p! - truth[name]!) : nil
            let row: [String: Any] = [
                "clip": name,
                "truth": truth[name] as Any,
                "err_f2p": err as Any,
                "ball_speed": metrics["ball_speed"] as? Double as Any,
                "speed_avg_foul_to_pins": f2p as Any,
                "rev_rate": metrics["rev_rate"] as? Double as Any,
                "basis": body["basis"] as? String as Any,
                "note": body["note"] as? String as Any,
                "reason_code": body["reason_code"] as? String as Any,
                "failed_stage": body["failed_stage"] as? String as Any,
                "latency_s": perf["latency_s"] as? Double as Any,
                "stage_ms": perf["stage_ms"] as? [String: Double] as Any,
                // the structured metrics (value + per-metric status + reason_code) — the DEC-128 parity payload
                "metrics_detailed": body["metrics_detailed"] as? [String: Any] as Any,
                "stage_report": body["stage_report"] as? [String: Any] as Any,
                "diag": body["diag"] as? [String: Any] as Any,
                "trajectory": body["trajectory"] as? [String: Any] as Any,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: row.compactMapValues { $0 is NSNull ? nil : $0 }),
               let s = String(data: data, encoding: .utf8) {
                print("ONDEV_GATE_ROW \(s)")
            }
        }
        print("ONDEV_GATE_END found=\(found)")
        if found == 0 {
            throw XCTSkip("no GateClips in the test bundle — add them via project.yml locally to run the gate")
        }
    }
}
