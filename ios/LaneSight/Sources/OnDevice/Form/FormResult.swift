import Foundation

/// A single form metric measurement — the Swift analogue of `models.shot.Measurement` as used by the form
/// pipeline. Values are already rounded to 3 dp (as `_m` does) so the on-device JSON matches the reference shape.
nonisolated struct FormMeasurement: Codable, Equatable {
    let metric: String
    let value: Double?
    let unit: String
    var confidence: Double
    var status: String                 // ok | best_effort | low_confidence | unavailable (mutable: slo-mo downgrade)
    var note: String?
    var display: String?               // "Speeds up" / "Above shoulder" / qualitative read-out
    var uncertainty: Double?
    var id: String?                    // fundamentals M-id (M1..M7) when this is a measured position
    var viewRequired: String?

    init(_ metric: String, _ value: Double?, _ unit: String, _ confidence: Double, _ status: String,
         note: String? = nil, display: String? = nil, uncertainty: Double? = nil,
         id: String? = nil, viewRequired: String? = nil) {
        self.metric = metric
        self.value = value.map { (($0 * 1000).rounded()) / 1000 }
        self.unit = unit
        self.confidence = ((confidence * 100).rounded()) / 100
        self.status = status
        self.note = note
        self.display = display
        self.uncertainty = uncertainty.map { (($0 * 1000).rounded()) / 1000 }
        self.id = id
        self.viewRequired = viewRequired
    }

    /// JSON object matching the reference Measurement dict (for POST /shots/metrics + outcome rows).
    var dict: [String: Any] {
        var d: [String: Any] = ["metric": metric, "unit": unit, "confidence": confidence,
                                "status": status, "source": "lanesight_form",
                                "algorithm_version": OnDeviceFormEngine.backendVersion]
        d["value"] = value as Any
        if let note { d["note"] = note }
        if let display { d["display"] = display }
        if let uncertainty { d["uncertainty"] = uncertainty }
        if let id { d["id"] = id }
        if let viewRequired { d["view_required"] = viewRequired }
        return d
    }
}

/// The per-stage report (DEC-122): decode / pose / swing_events / delivery_isolation / slowmo.
nonisolated struct FormStageOutcome: Codable {
    let status: String                 // ok | failed | skipped
    var reasonCode: String?
    var reason: String?
    var frames: Int?
}

/// The full on-device Form analysis — the Swift analogue of `analyze_form_clip`'s return. Everything the result
/// screen + the metrics-only server call + the DEC-122 outcome rows need.
nonisolated struct FormAnalysis {
    var formVersion: String
    var view: String                       // down_lane | bowler_facing | rear | unknown
    var viewInfo: (view: String, confidence: Double, reason: String)?
    var status: String                     // ok | unavailable
    var handed: String?
    var fps: Double

    /// FORM_P1 metrics keyed by metric name (pushaway_time … slide_length).
    var metrics: [String: FormMeasurement]
    /// M1–M7 measured positions (view-gated).
    var measuredPositions: [String: FormMeasurement]

    /// Located event times (seconds): E2,E3,E4,E5,E6,E7,E8 + first_step/slide_plant/slide_stop/hold_start/hold_end.
    var events: [String: Double?]
    /// The gated display events (a dropped event is nil), used by the gate + thumbnails.
    var eventsGateReasons: [String: String]
    var strikes: [(t: Double, foot: String)]
    var stepIntervals: [Double]
    var swingSource: String
    var slowmo: (isSlowmo: Bool, factor: Int, note: String)

    var stageReport: [String: FormStageOutcome]

    /// FORM_P1 ordering (matches analyze.FORM_P1).
    static let p1Keys: [(String, String)] = [
        ("pushaway_time", "s"), ("backswing_time", "s"), ("downswing_time", "s"), ("release_time", "s"),
        ("swing_time", "s"), ("approach_time", "s"), ("step_count", "count"),
        ("ball_start_step", "index"), ("rhythm_ratio", "ratio"), ("finish_hold", "s"),
        ("backswing_height_rel", "ratio"), ("drift_boards", "board"),
        ("timing_at_slide", "s"), ("slide_length", "inch"),
    ]

    /// The structured metrics JSON for POST /shots/metrics (capture_mode=form) + the Offline card + outcome rows.
    var metricsJSONObject: [String: Any] {
        var out: [String: Any] = [:]
        for (k, _) in FormAnalysis.p1Keys { if let m = metrics[k] { out[k] = m.dict } }
        return out
    }

    var eventsJSONObject: [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in events { out[k] = v as Any }
        return out
    }

    var stageReportJSONObject: [String: Any] {
        var out: [String: Any] = [:]
        for (k, s) in stageReport {
            var d: [String: Any] = ["status": s.status]
            if let rc = s.reasonCode { d["reason_code"] = rc }
            if let r = s.reason { d["reason"] = r }
            if let f = s.frames { d["frames"] = f }
            out[k] = d
        }
        return out
    }
}
