import XCTest
@testable import LaneSight

// DEC-117 device gate (item 4). Runs the 4 labelled clips through the NATIVE on-device engine ON THE PHONE and
// prints per-clip speed + rev + device cost (latency, peak memory, battery, thermal). Compared offline against
// Shayne's labelled truth (speed) and the server (rev). The clips live in the test bundle under GateClips/ (added
// locally via project.yml; gitignored, not committed — like the server regression tier, the test SKIPS if absent).
//
// Run on device:
//   xcodebuild test -scheme LaneSight -destination 'id=<device-udid>' \
//     -only-testing:LaneSightTests/OnDeviceGateTests
final class OnDeviceGateTests: XCTestCase {
    func testOnDeviceSpeedAndRevOnLabeledClips() async throws {
        // DEC-117/DEC-118: judge the iPhone engine on the original 4 validation clips PLUS the 11/1
        // speed_truth_1101 set (22 total). `truth` is the foul→pins average (59.44 ft / (pin−foul)/fps) from
        // Shayne's labels; clips absent from the test bundle SKIP. Most 11/1 clips are off-axis / ball-return /
        // mounted-POV framings the engine does NOT support (server eval: 1/18 within 0.3) — they're here so the
        // on-device engine is measured on the same spread, and the row prints Δ-vs-truth for the grep-able report.
        let truth: [String: Double] = [
            "IMG_8751": 17.872, "IMG_8752": 18.003, "IMG_8753": 18.275, "IMG_8754": 17.362,
            "IMG_8963": 17.74, "IMG_8964": 16.879, "IMG_8965": 17.49, "IMG_8966": 17.24, "IMG_8967": 17.12,
            "IMG_8968": 17.00, "IMG_8969": 18.139, "IMG_8970": 17.24, "IMG_8971": 17.48, "IMG_8972": 17.00,
            "IMG_8973": 17.74, "IMG_8974": 17.36, "IMG_8975": 18.00, "IMG_8976": 17.10, "IMG_8977": 16.88,
            "IMG_8978": 17.12, "IMG_8979": 17.74, "IMG_8981": 18.413,
        ]
        let clips = ["IMG_8751", "IMG_8752", "IMG_8753", "IMG_8754",
                     "IMG_8963", "IMG_8964", "IMG_8965", "IMG_8966", "IMG_8967", "IMG_8968", "IMG_8969",
                     "IMG_8970", "IMG_8971", "IMG_8972", "IMG_8973", "IMG_8974", "IMG_8975", "IMG_8976",
                     "IMG_8977", "IMG_8978", "IMG_8979", "IMG_8981"]
        let bundle = Bundle(for: type(of: self))
        var found = 0
        print("ONDEV_GATE_BEGIN")
        for clip in clips {
            guard let url = bundle.url(forResource: clip, withExtension: "mov")
                    ?? bundle.url(forResource: clip, withExtension: "MOV") else {
                print("ONDEV_GATE \(clip) MISSING_IN_BUNDLE")
                continue
            }
            found += 1
            let body = await OnDeviceShadow.run(clipURL: url, shotId: "gate-\(clip)", source: "upload",
                                                sessionId: nil, captureMode: "shot", appVersion: "gate")
            // Flatten the pieces we care about into one grep-able line of JSON.
            let metrics = body["metrics"] as? [String: Any] ?? [:]
            let perf = body["device_perf"] as? [String: Any] ?? [:]
            let f2p = metrics["speed_avg_foul_to_pins"] as? Double
            let err: Double? = (truth[clip] != nil && f2p != nil) ? (f2p! - truth[clip]!) : nil
            let row: [String: Any] = [
                "clip": clip,
                "truth": truth[clip] as Any,
                "err_f2p": err as Any,   // on-device foul→pins − truth (DEC-118 accuracy)
                "ball_speed": metrics["ball_speed"] as? Double as Any,
                "speed_avg_foul_to_pins": f2p as Any,   // DEC-117 truth-comparable
                "rev_rate": metrics["rev_rate"] as? Double as Any,
                "rev_sigma": metrics["rev_rate_sigma"] as? Double as Any,
                "basis": body["basis"] as? String as Any,
                "note": body["note"] as? String as Any,
                "latency_s": perf["latency_s"] as? Double as Any,
                "stage_ms": perf["stage_ms"] as? [String: Double] as Any,   // DEC-117 per-stage breakdown
                "peak_mem_mb": perf["peak_mem_mb"] as? Double as Any,
                "battery_delta": perf["battery_delta"] as? Double as Any,
                "thermal": perf["thermal_state"] as? String as Any,
                "diag": body["diag"] as? [String: Any] as Any,
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
