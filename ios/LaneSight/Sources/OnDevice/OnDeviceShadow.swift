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
        if let px = OnDeviceLaneDetector.referenceFrame(url: clipURL, at: 30) {
            let geo = OnDeviceLaneDetector.detect(pixelBuffer: px)
            let track = OnDeviceTracker.track(url: clipURL, geo: geo)
            peak = max(peak, currentFootprintBytes())
            let sp = OnDeviceTracker.speed(track: track, geo: geo)
            mph = sp.mph; basis = sp.basis; note = sp.note
        } else {
            note = "no reference frame"
        }
        peak = max(peak, currentFootprintBytes())

        let latency = Date().timeIntervalSince(t0)
        let battEnd = await MainActor.run { UIDevice.current.batteryLevel }
        let thermalEnd = ThermalWatch.describe(ProcessInfo.processInfo.thermalState)

        var metrics: [String: Any] = [:]
        if let m = mph { metrics["ball_speed"] = Double(m) }
        var perf: [String: Any] = [
            "latency_s": latency,
            "peak_mem_mb": Double(peak) / 1_048_576.0,
            "thermal_state": thermalEnd,
        ]
        if battStart >= 0, battEnd >= 0 { perf["battery_delta"] = Double(battStart - battEnd) }
        if thermalStart != thermalEnd { perf["thermal_transitions"] = "\(thermalStart)→\(thermalEnd)" }

        var body: [String: Any] = [
            "shot_id": shotId, "source": source, "capture_mode": captureMode,
            "basis": basis, "note": note, "metrics": metrics, "device_perf": perf,
            "algorithm_version": engineVersion, "app_version": appVersion,
        ]
        if let sid = sessionId { body["session_id"] = sid }
        return body
    }
}
