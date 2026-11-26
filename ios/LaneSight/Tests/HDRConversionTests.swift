import XCTest
import AVFoundation
@testable import LaneSight

/// DEC-133 HDR A/B harness: run the on-device SHOT engine on an HDR clip tone-mapped by `CaptureProbe.convertToSDR`
/// vs the native-SDR baseline of the same shot, and confirm tracking + speed match (a mismatched HDR tone-map
/// broke tracking — DEC-113). Reads the two clips from ~/LaneSightData (the simulator can read host paths); skips
/// if they aren't present. Not asserted hard on speed equality (prints the A/B) — fails only if HDR→SDR yields a
/// DRASTICALLY worse track (so a broken tone-map is caught).
@MainActor
final class HDRConversionTests: XCTestCase {
    // Bundled test resources (device-safe; the device can't read host paths). Copied into Tests/FormGateClips/.
    private func clip(_ name: String) -> URL? {
        Bundle(for: type(of: self)).url(forResource: name, withExtension: "mov")
            ?? Bundle(for: type(of: self)).url(forResource: name, withExtension: "MOV")
    }

    func testHDRtoSDRtrackingMatchesBaseline() async throws {
        guard let hdr = clip("IMG_8751_hdr"), let sdr = clip("IMG_8751_sdr") else {
            throw XCTSkip("IMG_8751_hdr.mov / IMG_8751_sdr.mov not bundled in the test target")
        }
        // 1) probe the HDR clip — it must be detected as HDR and convert to a valid SDR file.
        let info = CaptureProbe.probe(url: hdr, source: "upload")
        print("HDR probe: \(info?.width ?? 0)x\(info?.height ?? 0) \(info?.dynamicRange.rawValue ?? "?") \(info?.codec ?? "?")")
        guard let converted = await CaptureProbe.convertToSDR(hdr) else {
            return XCTFail("HDR→SDR conversion failed")
        }
        let convInfo = CaptureProbe.probe(url: converted, source: "upload")
        XCTAssertEqual(convInfo?.dynamicRange, .sdr, "converted clip should be SDR")

        // 2) run the shot engine on the converted-HDR and the native-SDR baseline, compare speed + track points.
        let a = await runEngine(converted, label: "HDR→SDR")
        let b = await runEngine(sdr, label: "SDR baseline")
        print("A/B  HDR→SDR speed=\(a.speed.map { String(format: "%.2f", $0) } ?? "nil") track=\(a.track)  |  SDR speed=\(b.speed.map { String(format: "%.2f", $0) } ?? "nil") track=\(b.track)")

        // Catch a broken tone-map: the HDR→SDR track must not collapse vs the SDR baseline.
        if b.track >= 10 {
            XCTAssertGreaterThanOrEqual(a.track, b.track / 2, "HDR→SDR track collapsed vs SDR baseline (broken tone-map)")
        }
        if let sa = a.speed, let sb = b.speed {
            print("speed delta HDR→SDR vs SDR = \(String(format: "%.2f", abs(sa - sb))) mph")
        }
    }

    private func runEngine(_ url: URL, label: String) async -> (speed: Double?, track: Int) {
        let body = await OnDeviceShadow.run(clipURL: url, shotId: UUID().uuidString, source: "upload",
                                            sessionId: nil, captureMode: "shot", appVersion: "test")
        let m = body["metrics"] as? [String: Any] ?? [:]
        let diag = body["diagnostics"] as? [String: Any] ?? (body["device_perf"] as? [String: Any]) ?? [:]
        let track = (diag["track_points"] as? Int) ?? (body["track_points"] as? Int) ?? 0
        return (m["ball_speed"] as? Double, track)
    }
}
