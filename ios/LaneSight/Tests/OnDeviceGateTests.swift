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
        let clips = ["IMG_8751", "IMG_8752", "IMG_8753", "IMG_8754"]
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
            let row: [String: Any] = [
                "clip": clip,
                "ball_speed": metrics["ball_speed"] as? Double as Any,
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
