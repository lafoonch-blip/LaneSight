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
        var avgFoulToPins: Float?
        var basis = "unavailable"
        var note = ""
        var revRpm: Float?
        var revSigma: Float?
        var revNote = ""
        var boards: BoardMetrics?
        var diag: [String: Any] = [:]       // DEC-117 Track A item 2: per-stage diagnostics for parity vs golden
        var stageMs: [String: Double] = [:]  // DEC-117 Track A item 1: per-stage timing breakdown (ms)
        func stage<T>(_ name: String, _ body: () -> T) -> T {
            let s = Date(); let r = body(); stageMs[name] = Date().timeIntervalSince(s) * 1000; return r
        }
        // DEC-117 Track A: detect on the rotation-corrected stabilized BACKGROUND PLATE (temporal median), the
        // same input the Python find_lanes(bg) + ios_parity_golden use — not a lone raw frame.
        let plateResult = stage("plate") { OnDeviceDecode.backgroundPlate(url: clipURL) }
        if let (plate, rot) = plateResult {
            diag["rotation"] = "\(rot)"
            let geo = stage("detect") { OnDeviceLaneDetector.detect(pixelBuffer: plate) }
            diag["lane_found"] = geo.lanes.first != nil
            diag["lanes_detected"] = geo.lanes.count
            diag["foul_line_y"] = geo.foulLineY as Any
            if let vp = geo.vanishingPoint { diag["vp"] = [Double(vp.x), Double(vp.y)] }
            if let l = geo.lanes.first {
                diag["left_ab"] = [Double(l.left.a), Double(l.left.b)]
                diag["right_ab"] = [Double(l.right.a), Double(l.right.b)]
                diag["y_near_far"] = [l.yNear, l.yFar]
            }
            let track = stage("track") { OnDeviceTracker.track(url: clipURL, geo: geo, rot: rot) }
            peak = max(peak, currentFootprintBytes())
            diag["frames_scanned"] = track.framesScanned
            diag["candidate_frames"] = track.candidateFrames
            diag["track_points"] = track.points.count
            diag["span_frac"] = Double(track.spanFrac)
            if let it = track.impactT { diag["impact_t_detected"] = it }
            let sp = stage("speed") { OnDeviceTracker.speed(track: track, geo: geo) }
            mph = sp.mph; basis = sp.basis; note = sp.note
            avgFoulToPins = sp.avgFoulToPinsMph
            if let tr = sp.tRelease { diag["t_release"] = tr }
            if let ti = sp.tImpact { diag["t_impact"] = ti }
            if let fc = sp.tFoulCross { diag["t_foul_cross"] = fc }
            if let a = sp.avgFoulToPinsMph { diag["speed_avg_foul_to_pins"] = Double(a) }
            if let tr = sp.tRelease, let ti = sp.tImpact { diag["foul_to_impact_s"] = ti - tr }
            diag["first_failing_stage"] = (geo.lanes.first == nil) ? "lane"
                : (track.points.count < 6 ? "track"
                : (sp.mph == nil ? "speed" : "none"))
            // DEC-117: rev rate (shadow; compile/validation pending). Geometry-free beyond the track, so it runs
            // even when speed is unavailable.
            let rev = stage("rev") { OnDeviceRevRate.measure(url: clipURL, track: track.points, geo: geo) }
            revRpm = rev.rpm; revSigma = rev.sigmaRpm; revNote = rev.note
            if basis == "unavailable", rev.rpm != nil { basis = "best_effort" }   // rev stands alone (DEC-111)
            // DEC-127: BOARD metrics via the lane-plane homography (entry/arrows/laydown/breakpoint + angles).
            boards = stage("boards") { OnDeviceBoards.compute(track: track, geo: geo, speed: sp) }
            if let b = boards {
                diag["right_handed"] = b.rightHanded as Any
                if let v = b.entryBoard.value { diag["entry_board"] = v }
                if let v = b.arrowsBoard.value { diag["arrows_board"] = v }
                if let v = b.breakpointBoard.value { diag["breakpoint_board"] = v }
            }
            peak = max(peak, currentFootprintBytes())
        } else {
            note = "no background plate"
            diag["first_failing_stage"] = "plate"
        }
        peak = max(peak, currentFootprintBytes())

        let latency = Date().timeIntervalSince(t0)
        let battEnd = await MainActor.run { UIDevice.current.batteryLevel }
        let thermalEnd = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)

        var metrics: [String: Any] = [:]
        if let m = mph { metrics["ball_speed"] = Double(m) }
        if let a = avgFoulToPins { metrics["speed_avg_foul_to_pins"] = Double(a) }
        if let rv = revRpm { metrics["rev_rate"] = Double(rv) }
        if let rs = revSigma { metrics["rev_rate_sigma"] = Double(rs) }
        if mph == nil, !revNote.isEmpty { note = note.isEmpty ? revNote : note + " | rev: " + revNote }

        // DEC-127: the structured metrics record the /shots/metrics path forwards — value + status + unit + note
        // per metric, so a MEASURED metric is 'ok' (counts for the Score) and an unmeasurable one is 'unavailable'
        // + a reason (never a fabricated number). The flat `metrics` scalars above stay for the dev tool + the
        // older /analysis/shadow diag.
        func cell(_ v: Double?, _ unit: String, status: String = "ok", note cn: String? = nil) -> [String: Any] {
            var d: [String: Any] = ["status": v != nil ? status : "unavailable", "unit": unit]
            if let v { d["value"] = v }
            if let cn { d["note"] = cn }
            return d
        }
        // DEC-127 parity: mirror cv/pipeline.py's per-metric status EXACTLY (so a metric is never 'measured' on
        // one engine and best_effort/unavailable on the other). ball_speed + segment speeds = best_effort;
        // rev_rate = calibrated_estimate; foul→pins = best_effort (approximated impact, DEC-112); the FAR-LANE
        // metrics are GATED to unavailable until DEC-065 validation; near-lane boards stay measured ('ok').
        let farLane: Set<String> = ["entry_board", "entry_angle", "entry_angle_52_55",
                                    "breakpoint_board", "breakpoint_distance", "speed_late"]
        var detailed: [String: Any] = [
            "ball_speed": cell(mph.map(Double.init), "mph", status: "best_effort", note: mph == nil ? note : nil),
            "speed_avg_foul_to_pins": cell(avgFoulToPins.map(Double.init), "mph", status: "best_effort",
                                           note: "full-lane average; impact frame approximated (DEC-112)"),
            "rev_rate": cell(revRpm.map(Double.init), "rpm", status: "calibrated_estimate",
                             note: revRpm == nil ? revNote : nil),
        ]
        if let rs = revSigma { if var r = detailed["rev_rate"] as? [String: Any] { r["uncertainty"] = Double(rs); detailed["rev_rate"] = r } }
        var trajectory: [String: Any] = [:]
        if let b = boards {
            for (key, bc) in b.metricPairs() {
                let unit = key.hasSuffix("angle") || key == "launch_angle" ? "deg"
                         : (key == "breakpoint_distance" ? "ft" : "board")
                if farLane.contains(key) {
                    // gated (DEC-065) — unavailable with the gate reason even when the engine computed a value
                    detailed[key] = ["status": "unavailable", "unit": unit,
                                     "note": "Back-lane metric gated until Phase-2 validation (DEC-065).",
                                     "reason_code": "FAR_LANE_UNVALIDATED"]
                } else {
                    detailed[key] = cell(bc.value, unit, status: bc.status == "ok" ? "ok" : "unavailable", note: bc.note)
                    if bc.status == "ok", let v = bc.value { metrics[key] = v }   // measured scalar for the dev tool
                }
            }
            // DEC-127: the ball path for the shot-card lane view. The server builds path_fit from `smoothed`.
            if !b.curveZBoard.isEmpty {
                trajectory["smoothed"] = b.curveZBoard.map { ["z_ft": $0[0], "board": $0[1]] }
                trajectory["series"] = b.seriesZBoard.map { ["z_ft": $0[0], "board": $0[1]] }
            }
        }
        // DEC-128 plausibility bounds — parity with cv/pipeline.py + failures.IMPLAUSIBLE_VALUE. A value physically
        // off the lane is NEVER shown as measured: boards live on a 39-board lane (1–39), ball speed 8–30 mph, rev
        // 100–700 rpm. Out of band ⇒ unavailable + IMPLAUSIBLE_VALUE (the engine mis-tracked or picked the wrong
        // lane). The near-lane boards all ride one homography, so if any is off the lane the whole near-lane read
        // is corrupt (catches the wrong-lane case: arrows 37 + board_at_7ft 50) — drop all of them and the path.
        let nearBoards: Set<String> = ["laydown_board", "board_at_7ft", "arrows_board"]
        let allBoards: Set<String> = nearBoards.union(["breakpoint_board", "entry_board"])
        let speedKeys: Set<String> = ["ball_speed", "speed_avg_foul_to_pins", "speed_release", "speed_early", "speed_late"]
        func outOfBand(_ key: String, _ v: Double) -> Bool {
            if allBoards.contains(key) { return v < 1 || v > 39 }
            if speedKeys.contains(key) { return v < 8 || v > 30 }
            if key == "rev_rate" { return v < 100 || v > 700 }
            return false
        }
        func cellValue(_ key: String) -> Double? { (detailed[key] as? [String: Any])?["value"] as? Double }
        func markImplausible(_ key: String) {
            guard let c = detailed[key] as? [String: Any] else { return }
            let unit = c["unit"] as? String ?? ""
            let vtxt = (c["value"] as? Double).map { String(format: "%.1f", $0) } ?? "?"
            detailed[key] = ["status": "unavailable", "unit": unit, "reason_code": "IMPLAUSIBLE_VALUE",
                             "note": "Measured \(vtxt) \(unit) is out of range — not a real read (the engine likely mis-tracked or picked the wrong lane)."]
            metrics.removeValue(forKey: key)
        }
        let nearCorrupt = nearBoards.contains { k in cellValue(k).map { outOfBand(k, $0) } ?? false }
        for key in detailed.keys {
            guard let v = cellValue(key) else { continue }
            if outOfBand(key, v) || (nearCorrupt && nearBoards.contains(key)) { markImplausible(key) }
        }
        if nearCorrupt { trajectory.removeAll() }   // the path rides the same corrupt plane — don't draw it
        var perf: [String: Any] = [
            "latency_s": latency,
            "peak_mem_mb": Double(peak) / 1_048_576.0,
            "thermal_state": thermalEnd,
            "stage_ms": stageMs,          // DEC-117 Track A item 1: per-stage breakdown (reference_frame/detect/track/speed/rev)
        ]
        if battStart >= 0, battEnd >= 0 { perf["battery_delta"] = Double(battStart - battEnd) }
        if thermalStart != thermalEnd { perf["thermal_transitions"] = "\(thermalStart)→\(thermalEnd)" }

        // DEC-127: propagate the REAL failing stage + a server-matching reason_code (not a blanket
        // METRIC_UNAVAILABLE), so every unavailable metric shows WHY — the same codes the server raises.
        // DEC-122/DEC-128: emit a COMPLETE per-stage report for EVERY attempt (not just failures), so
        // analysis_stage_outcome has platform=ios rows for success and failure alike. Canonical server stage
        // names (lane → track → metrics); durations sum the sub-steps that make up each stage. The failing stage
        // carries the server-matching reason_code; downstream stages that never ran are 'skipped'.
        let failStage = diag["first_failing_stage"] as? String
        var reasonCode: String? = nil, failedStage: String? = nil
        var stageReport: [String: Any] = [:]
        let laneMs = (stageMs["plate"] ?? 0) + (stageMs["detect"] ?? 0)
        let trackMs = stageMs["track"] ?? 0
        let metricsMs = (stageMs["speed"] ?? 0) + (stageMs["boards"] ?? 0) + (stageMs["rev"] ?? 0)
        func stageRow(_ status: String, _ code: String?, _ ms: Double) -> [String: Any] {
            var d: [String: Any] = ["status": status, "duration_ms": ms]
            if let code { d["reason_code"] = code }
            return d
        }
        switch failStage {
        case "plate", "lane":
            reasonCode = "LANE_NOT_DETECTED"; failedStage = "lane"
            stageReport["lane"] = stageRow("failed", "LANE_NOT_DETECTED", laneMs)
            stageReport["track"] = stageRow("skipped", nil, 0)
            stageReport["metrics"] = stageRow("skipped", nil, 0)
        case "track":
            reasonCode = "BALL_TRACK_NOT_FOUND"; failedStage = "track"
            stageReport["lane"] = stageRow("ok", nil, laneMs)
            stageReport["track"] = stageRow("failed", "BALL_TRACK_NOT_FOUND", trackMs)
            stageReport["metrics"] = stageRow("skipped", nil, 0)
        case "speed":
            reasonCode = "TRACK_TOO_SPARSE_FOR_SPEED"; failedStage = "metrics"
            stageReport["lane"] = stageRow("ok", nil, laneMs)
            stageReport["track"] = stageRow("ok", nil, trackMs)
            stageReport["metrics"] = stageRow("failed", "TRACK_TOO_SPARSE_FOR_SPEED", metricsMs)
        default:   // "none" (success) or nil — the chain ran end to end
            stageReport["lane"] = stageRow("ok", nil, laneMs)
            stageReport["track"] = stageRow("ok", nil, trackMs)
            if nearCorrupt {   // DEC-128: speed ran but the near-lane plane was off-lane → metrics unreliable
                reasonCode = "IMPLAUSIBLE_VALUE"; failedStage = "metrics"
                stageReport["metrics"] = stageRow("failed", "IMPLAUSIBLE_VALUE", metricsMs)
            } else {
                stageReport["metrics"] = stageRow("ok", nil, metricsMs)
            }
        }
        var body: [String: Any] = [
            "shot_id": shotId, "source": source, "capture_mode": captureMode,
            "basis": basis, "note": note, "metrics": metrics, "metrics_detailed": detailed,
            "device_perf": perf, "diag": diag,
            "algorithm_version": engineVersion, "app_version": appVersion,
        ]
        if !trajectory.isEmpty { body["trajectory"] = trajectory }
        if let reasonCode { body["reason_code"] = reasonCode }
        if let failedStage { body["failed_stage"] = failedStage }
        if !stageReport.isEmpty { body["stage_report"] = stageReport }
        if let sid = sessionId { body["session_id"] = sid }
        return body
    }
}
