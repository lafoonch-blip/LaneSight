import Foundation
import UIKit

/// DEC-106 shadow runner. After the server analyses a shot, the app runs the NATIVE on-device engine on the
/// same clip in the background and submits the result as a `platform:'ios'` analysis_attempt (DEC-103). It is
/// NEVER shown to the user and NEVER feeds Score/coaching — the server stays authoritative. Purpose: collect
/// on-device vs server (and, once the DEC-094 ground-truth set exists, vs truth) data so each metric can be
/// promoted per the DEC-106 gates. No flip happens on device.
enum OnDeviceShadow {
    nonisolated static let engineVersion = "ios-ondevice-0.1"

    /// Runs stabilise-free chain referenceFrame → detect → track → speed and measures device cost. Returns a
    /// JSON-ready body for POST /analysis/shadow. `nonisolated` + value-type output so it runs off the main
    /// actor; battery reads hop to the main actor (UIDevice is main-actor only).
    nonisolated static func run(clipURL: URL, shotId: String, source: String, sessionId: String?,
                                captureMode: String, appVersion: String) async -> [String: Any] {
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }
        let battStart = await MainActor.run { UIDevice.current.batteryLevel }      // -1 if unknown
        let thermalStart = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)
        let t0 = Date()

        var peak = currentFootprintBytes()
        var mph: Float?
        var basis = "unavailable"
        var note = ""
        var revRpm: Float?
        var revSigma: Float?
        var revNote = ""
        var diag: [String: Any] = [:]       // DEC-117 Track A item 2: per-stage diagnostics for parity vs golden
        var stageMs: [String: Double] = [:]  // DEC-117 Track A item 1: per-stage timing breakdown (ms)
        func stage<T>(_ name: String, _ body: () -> T) -> T {
            let s = Date(); let r = body(); stageMs[name] = Date().timeIntervalSince(s) * 1000; return r
        }
        let refFrame = stage("reference_frame") { OnDeviceLaneDetector.referenceFrame(url: clipURL, at: 30) }
        if let px = refFrame {
            let geo = stage("detect") { OnDeviceLaneDetector.detect(pixelBuffer: px) }
            diag["lane_found"] = geo.lanes.first != nil
            diag["lanes_detected"] = geo.lanes.count
            diag["foul_line_y"] = geo.foulLineY as Any
            if let vp = geo.vanishingPoint { diag["vp"] = [Double(vp.x), Double(vp.y)] }
            if let l = geo.lanes.first {
                diag["left_ab"] = [Double(l.left.a), Double(l.left.b)]
                diag["right_ab"] = [Double(l.right.a), Double(l.right.b)]
                diag["y_near_far"] = [l.yNear, l.yFar]
            }
            let track = stage("track") { OnDeviceTracker.track(url: clipURL, geo: geo) }
            peak = max(peak, currentFootprintBytes())
            diag["frames_scanned"] = track.framesScanned
            diag["candidate_frames"] = track.candidateFrames
            diag["track_points"] = track.points.count
            diag["span_frac"] = Double(track.spanFrac)
            if let it = track.impactT { diag["impact_t_detected"] = it }
            let sp = stage("speed") { OnDeviceTracker.speed(track: track, geo: geo) }
            mph = sp.mph; basis = sp.basis; note = sp.note
            if let tr = sp.tRelease { diag["t_release"] = tr }
            if let ti = sp.tImpact { diag["t_impact"] = ti }
            if let tr = sp.tRelease, let ti = sp.tImpact { diag["foul_to_impact_s"] = ti - tr }
            diag["first_failing_stage"] = (geo.lanes.first == nil) ? "lane"
                : (track.points.count < 6 ? "track"
                : (sp.mph == nil ? "speed" : "none"))
            // DEC-117: rev rate (shadow; compile/validation pending). Geometry-free beyond the track, so it runs
            // even when speed is unavailable.
            let rev = stage("rev") { OnDeviceRevRate.measure(url: clipURL, track: track.points, geo: geo) }
            revRpm = rev.rpm; revSigma = rev.sigmaRpm; revNote = rev.note
            if basis == "unavailable", rev.rpm != nil { basis = "best_effort" }   // rev stands alone (DEC-111)
            peak = max(peak, currentFootprintBytes())
        } else {
            note = "no reference frame"
            diag["first_failing_stage"] = "reference_frame"
        }
        peak = max(peak, currentFootprintBytes())

        let latency = Date().timeIntervalSince(t0)
        let battEnd = await MainActor.run { UIDevice.current.batteryLevel }
        let thermalEnd = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)

        var metrics: [String: Any] = [:]
        if let m = mph { metrics["ball_speed"] = Double(m) }
        if let rv = revRpm { metrics["rev_rate"] = Double(rv) }
        if let rs = revSigma { metrics["rev_rate_sigma"] = Double(rs) }
        if mph == nil, !revNote.isEmpty { note = note.isEmpty ? revNote : note + " | rev: " + revNote }
        var perf: [String: Any] = [
            "latency_s": latency,
            "peak_mem_mb": Double(peak) / 1_048_576.0,
            "thermal_state": thermalEnd,
            "stage_ms": stageMs,          // DEC-117 Track A item 1: per-stage breakdown (reference_frame/detect/track/speed/rev)
        ]
        if battStart >= 0, battEnd >= 0 { perf["battery_delta"] = Double(battStart - battEnd) }
        if thermalStart != thermalEnd { perf["thermal_transitions"] = "\(thermalStart)→\(thermalEnd)" }

        var body: [String: Any] = [
            "shot_id": shotId, "source": source, "capture_mode": captureMode,
            "basis": basis, "note": note, "metrics": metrics, "device_perf": perf,
            "diag": diag,
            "algorithm_version": engineVersion, "app_version": appVersion,
        ]
        if let sid = sessionId { body["session_id"] = sid }
        return body
    }
}
