import Foundation
import AVFoundation
import Vision
import UIKit

/// DEC-106 Form shadow. Runs Apple **Vision** body-pose (VNDetectHumanBodyPoseRequest) on-device over a form
/// clip and derives the same swing events + phase metrics as the Python reference (`form/pose.py`), so we can
/// measure on-device-vs-reference (and, via DEC-094, vs ground-truth event labels). NEVER shown to the user,
/// NEVER scored — submitted to POST /analysis/shadow with capture_mode='form', platform='ios'.
///
/// Faithful to the reference's SCALE-FREE strategy (torso-relative positions, fraction-of-peak-speed
/// thresholds, wrist-arc primary) and its event codes. v0.1 deliberately defers the reference's refinements —
/// slo-mo factor correction, on-lane ball-track release refinement, visibility-weighted 3-point foot fusion,
/// and delivery-isolation burst gating — because Vision's joint set differs from BlazePose's 33 and the point
/// of the shadow is to MEASURE the gap, not assume parity. Those land as the shadow matures.
enum OnDeviceFormShadow {
    nonisolated static let engineVersion = "ios-form-0.1"

    private struct Pose {
        var t: Double
        var wrist: CGPoint?
        var shoulderMid: CGPoint?
        var hipMid: CGPoint?
        var ankle: CGPoint?
        var conf: Float
    }

    /// Mirrors OnDeviceShadow.run: CV + device-perf measured together, returns the JSON body for /analysis/shadow.
    nonisolated static func run(clipURL: URL, shotId: String, source: String, sessionId: String?,
                               handed: String, appVersion: String) async -> [String: Any] {
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }
        let battStart = await MainActor.run { UIDevice.current.batteryLevel }
        let thermalStart = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)
        let t0 = Date()
        var peak = currentFootprintBytes()

        let poses = collectPoses(url: clipURL, rightHanded: handed.lowercased() != "left")
        peak = max(peak, currentFootprintBytes())
        let r = detect(poses: poses)

        let latency = Date().timeIntervalSince(t0)
        let battEnd = await MainActor.run { UIDevice.current.batteryLevel }
        let thermalEnd = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)

        var perf: [String: Any] = ["latency_s": latency,
                                   "peak_mem_mb": Double(peak) / 1_048_576.0,
                                   "thermal_state": thermalEnd,
                                   "pose_confidence": r.poseConfidence]
        if battStart >= 0, battEnd >= 0 { perf["battery_delta"] = Double(battStart - battEnd) }
        if thermalStart != thermalEnd { perf["thermal_transitions"] = "\(thermalStart)→\(thermalEnd)" }

        var body: [String: Any] = [
            "shot_id": shotId, "source": source, "capture_mode": "form",
            "basis": r.basis, "note": r.note, "events": r.events, "metrics": r.metrics,
            "device_perf": perf, "algorithm_version": engineVersion, "app_version": appVersion,
        ]
        if let sid = sessionId { body["session_id"] = sid }
        return body
    }

    // ---- Vision pose extraction: one VNDetectHumanBodyPoseRequest per frame (streamed, like the ball engine) ----
    nonisolated private static func collectPoses(url: URL, rightHanded: Bool) -> [Pose] {
        var out: [Pose] = []
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return out }
        let rdOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        guard reader.canAdd(rdOut) else { return out }
        reader.add(rdOut); reader.startReading()
        let req = VNDetectHumanBodyPoseRequest()
        while reader.status == .reading, let sb = rdOut.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return out }   // shadow cap / superseded (P0 2026-10-29)
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            let handler = VNImageRequestHandler(cvPixelBuffer: px, orientation: .up, options: [:])
            try? handler.perform([req])
            guard let obs = req.results?.first else {
                out.append(Pose(t: t, wrist: nil, shoulderMid: nil, hipMid: nil, ankle: nil, conf: 0)); continue
            }
            // Vision is origin bottom-left; flip to image-y (down) so the reference's "min y = apex" logic applies.
            func pt(_ j: VNHumanBodyPoseObservation.JointName) -> (CGPoint?, Float) {
                if let p = try? obs.recognizedPoint(j), p.confidence > 0.1 {
                    return (CGPoint(x: p.location.x, y: 1 - p.location.y), p.confidence)
                }
                return (nil, 0)
            }
            let (wrist, wc) = pt(rightHanded ? .rightWrist : .leftWrist)
            let (rs, rsc) = pt(.rightShoulder); let (ls, lsc) = pt(.leftShoulder)
            let (rh, rhc) = pt(.rightHip); let (lh, lhc) = pt(.leftHip)
            let (ankle, ac) = pt(rightHanded ? .rightAnkle : .leftAnkle)
            out.append(Pose(t: t, wrist: wrist, shoulderMid: midpoint(rs, ls), hipMid: midpoint(rh, lh),
                            ankle: ankle, conf: meanOf([wc, rsc, lsc, rhc, lhc, ac])))
        }
        return out
    }

    nonisolated private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a = a, let b = b else { return a ?? b }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    nonisolated private static func meanOf(_ xs: [Float]) -> Float {
        let v = xs.filter { $0 > 0 }; return v.isEmpty ? 0 : v.reduce(0, +) / Float(v.count)
    }
    nonisolated private static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

    private struct FormResult {
        var events: [String: Double]; var metrics: [String: Double]
        var basis: String; var note: String; var poseConfidence: Double
    }

    // ---- event detection, scale-free, mirroring form/pose.py ----
    nonisolated private static func detect(poses: [Pose]) -> FormResult {
        let fail = { (n: String) in FormResult(events: [:], metrics: [:], basis: "unavailable", note: n, poseConfidence: 0) }
        let valid = poses.enumerated().filter { $0.element.wrist != nil }
        guard valid.count >= 10 else { return fail("insufficient pose frames") }

        // torso scale = median shoulder->hip distance (scale-free normaliser)
        let torsos = poses.compactMap { p -> Double? in
            guard let s = p.shoulderMid, let h = p.hipMid else { return nil }; return dist(s, h) }
        guard !torsos.isEmpty else { return fail("no torso") }
        let torso = torsos.sorted()[torsos.count / 2]
        guard torso > 1e-4 else { return fail("degenerate torso") }

        let n = poses.count
        func wy(_ i: Int) -> Double? { poses[i].wrist.map { Double($0.y) } }
        // wrist speed (per second), scale-free (÷ torso)
        var speed = [Double](repeating: 0, count: n)
        for i in 1..<n {
            if let a = poses[i].wrist, let b = poses[i - 1].wrist {
                let dt = poses[i].t - poses[i - 1].t
                if dt > 1e-4 { speed[i] = dist(a, b) / torso / dt }
            }
        }
        // E6 bottom of arc = frame with the LOWEST wrist (max image-y) — the deepest point of the swing
        var e6 = -1; var maxY = -1.0
        for i in 0..<n { if let y = wy(i), y > maxY { maxY = y; e6 = i } }
        guard e6 > 1 else { return fail("no swing bottom") }
        // E4 top of backswing = highest wrist (min image-y) BEFORE E6
        var e4 = -1; var minY = 2.0
        for i in 0..<e6 { if let y = wy(i), y < minY { minY = y; e4 = i } }
        guard e4 >= 1, e4 < e6 else { return fail("no backswing apex") }
        // E2 ball start = first frame (before E4) where wrist speed exceeds max(0.05, 0.30 * peak-before-E6)
        let peak = speed[0..<e6].max() ?? 0
        let thr = max(0.05, 0.30 * peak)
        var e2 = -1
        for i in 1...e4 where speed[i] > thr { e2 = i; break }
        if e2 < 0 { e2 = max(1, e4 - 1) }
        // E3 pushaway end = descending crossing of bally=(wrist_y+0.45*torso) through hip line, before E4;
        // fallback to E2 (rear view, where the hip crossing isn't observable)
        var e3 = e2
        for i in stride(from: e4, through: e2 + 1, by: -1) {
            guard let w0 = wy(i), let w1 = wy(i - 1), let hip = poses[i].hipMid.map({ Double($0.y) }) else { continue }
            let b0 = w0 + 0.45 * torso, b1 = w1 + 0.45 * torso
            if b1 <= hip && b0 >= hip { e3 = i; break }     // crossed below the hip (descending in image-y)
        }
        let e7 = min(e6 + 1, n - 1)                          // release ≈ one frame past the bottom (v0: no ball refine)

        // slide stop / step count from bowling-side ankle speed (v0: single ankle, not 3-point fused)
        var ankleSpeed = [Double](repeating: 0, count: n)
        for i in 1..<n {
            if let a = poses[i].ankle, let b = poses[i - 1].ankle {
                let dt = poses[i].t - poses[i - 1].t
                if dt > 1e-4 { ankleSpeed[i] = dist(a, b) / torso / dt }
            }
        }
        let aPeak = ankleSpeed.max() ?? 0
        var strikes: [Int] = []                             // local minima (foot plants) ≥ 0.20 s apart
        for i in 2..<(n - 1) where ankleSpeed[i] < ankleSpeed[i - 1] && ankleSpeed[i] <= ankleSpeed[i + 1]
            && ankleSpeed[i] < 0.35 * aPeak {
            if strikes.isEmpty || poses[i].t - poses[strikes.last!].t >= 0.20 { strikes.append(i) }
        }
        let stepCount = strikes.filter { $0 <= e7 }.count
        let slideStopT = strikes.last.map { poses[$0].t } ?? poses[e7].t

        func T(_ i: Int) -> Double { poses[i].t }
        var events: [String: Double] = [
            "ball_start_s": T(e2), "pushaway_end_s": T(e3), "top_of_swing_s": T(e4),
            "slide_stop_s": slideStopT, "release_s": T(e7)]

        // gate_events (reference thresholds): chronological, ball_start→release in 1.3–2.5 s, release near slide stop
        let chrono = T(e2) <= T(e3) && T(e3) <= T(e4) && T(e4) < T(e6) && T(e6) <= T(e7)
        let span = T(e7) - T(e2)
        let nearSlide = (T(e7) >= slideStopT - 0.10) && (T(e7) <= slideStopT + 0.15)
        if !(chrono && span >= 1.3 && span <= 2.5 && nearSlide) {
            return FormResult(events: events, metrics: [:], basis: "unavailable",
                              note: "events failed gate (chrono=\(chrono) span=\(String(format: "%.2f", span)) nearSlide=\(nearSlide))",
                              poseConfidence: confWindow(poses, e2, e7))
        }
        let backswing = T(e4) - T(e3), downswing = T(e6) - T(e4)
        var metrics: [String: Double] = [
            "pushaway_time": T(e3) - T(e2), "backswing_time": backswing, "downswing_time": downswing,
            "release_time": T(e7) - T(e6), "swing_time": T(e7) - T(e2), "step_count": Double(stepCount)]
        if backswing > 1e-3 { metrics["rhythm_ratio"] = downswing / backswing }
        return FormResult(events: events, metrics: metrics, basis: "best_effort", note: "",
                          poseConfidence: confWindow(poses, e2, e7))
    }

    nonisolated private static func confWindow(_ poses: [Pose], _ a: Int, _ b: Int) -> Double {
        let w = poses[max(0, a)...min(poses.count - 1, b)].map { Double($0.conf) }.filter { $0 > 0 }
        return w.isEmpty ? 0 : w.reduce(0, +) / Double(w.count)
    }
}
