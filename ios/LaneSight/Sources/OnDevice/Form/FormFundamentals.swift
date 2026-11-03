import Foundation

/// Form fundamentals v1 (DEC-057) — the pure decision/geometry layer, ported from `lanesight_core/form/fundamentals.py`.
/// measured_positions M1–M7, view gating, timing checkpoints T1–T4, swing-timing-vs-baseline, coaching cues.
enum FormFundamentals {
    typealias Frame = FormPoseLandmarker.Frame
    typealias LM = FormPoseLandmarker.LM
    static let version = "form-fundamentals-0.1.0"

    static let foulLineReason = "needs foul-line detection with floor-plane scale — not calibrated on this framing "
        + "(same unresolved homography as drift/slide length; TRAINING_VIDEOS_CALIBRATED_METRICS)"
    static let spineFwdNote = "absolute forward tilt needs a side view; from a rear/front clip this is a provisional "
        + "frontal-plane tilt only"

    /// Which capture views each position can be measured from (POSITION_VIEWS).
    static let positionViews: [String: Set<String>] = [
        "spine_tilt": ["down_lane"],
        "balance_arm": ["rear", "bowler_facing"],
        "shoulder_tilt": ["rear", "bowler_facing"],
        "follow_through": ["down_lane", "rear", "bowler_facing", "unknown"],
        "finish_hold": ["down_lane", "rear", "bowler_facing", "unknown"],
        "pendulum": ["down_lane", "rear", "bowler_facing", "unknown"],
        "foul_line_distance": [],
    ]
    static let allViews: Set<String> = ["down_lane", "bowler_facing", "rear", "unknown"]

    // MARK: geometry helpers
    private static func sideIndices(_ handed: String?) -> (bowlSh: Int, bowlWr: Int, offSh: Int, offWr: Int) {
        if (handed ?? "R").trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("L") {
            return (LM.lShoulder, LM.lWrist, LM.rShoulder, LM.rWrist)
        }
        return (LM.rShoulder, LM.rWrist, LM.lShoulder, LM.lWrist)
    }
    private static func idxAt(_ t: [Double], _ ev: Double?) -> Int? {
        guard let ev, !t.isEmpty else { return nil }
        var bi = 0, bv = Double.infinity
        for i in 0..<t.count { let d = abs(t[i] - ev); if d < bv { bv = d; bi = i } }
        return bi
    }
    private static func pt(_ frames: [Frame], _ k: Int?, _ idx: Int?) -> (Double, Double)? {
        guard let k, let idx, idx < frames.count else { return nil }
        let r = frames[idx].lm
        let x = Double(r[k][0]), y = Double(r[k][1]), vis = Double(r[k][3])
        if x.isNaN || y.isNaN || vis < FormSignal.MIN_VIS { return nil }
        return (x, y)
    }
    private static func mid(_ a: (Double, Double)?, _ b: (Double, Double)?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
    }
    private static func angleFromVertical(_ top: (Double, Double)?, _ bottom: (Double, Double)?) -> Double? {
        guard let top, let bottom else { return nil }
        let dx = top.0 - bottom.0
        let dy = bottom.1 - top.1
        if dx == 0 && dy == 0 { return nil }
        return abs(atan2(dx, dy) * 180 / .pi)
    }
    private static func angleFromHorizontal(_ left: (Double, Double)?, _ right: (Double, Double)?) -> Double? {
        guard let left, let right else { return nil }
        let dx = right.0 - left.0, dy = right.1 - left.1
        if dx == 0 && dy == 0 { return nil }
        return atan2(dy, dx) * 180 / .pi
    }
    private static func angleBetween(_ center: (Double, Double)?, _ a: (Double, Double)?, _ b: (Double, Double)?) -> Double? {
        guard let center, let a, let b else { return nil }
        let v1 = (a.0 - center.0, a.1 - center.1)
        let v2 = (b.0 - center.0, b.1 - center.1)
        let n1 = hypot(v1.0, v1.1), n2 = hypot(v2.0, v2.1)
        if n1 < 1e-6 || n2 < 1e-6 { return nil }
        let cos = Swift.max(-1.0, Swift.min(1.0, (v1.0 * v2.0 + v1.1 * v2.1) / (n1 * n2)))
        return acos(cos) * 180 / .pi
    }

    // MARK: measured positions M1–M7
    /// measured_positions(t, lms, events, torso, handed, metrics) — view-agnostic geometry; gate() applies views.
    static func measuredPositions(_ t: [Double], _ frames: [Frame], events: [String: Double?],
                                  torso: Double, handed: String?, metrics: [String: FormMeasurement]) -> [String: FormMeasurement] {
        let si = sideIndices(handed)
        let E7 = events["E7"] ?? nil
        let k7 = idxAt(t, E7)
        var out = [String: FormMeasurement]()

        // M1 foul-line distance — never (no floor scale)
        out["foul_line_distance"] = unavailPos("M1", "foul_line_distance", "inch", foulLineReason, "rear/side + floor scale")

        // M2 spine tilt at release + consistency
        let sh = mid(pt(frames, LM.lShoulder, k7), pt(frames, LM.rShoulder, k7))
        let hp = mid(pt(frames, LM.lHip, k7), pt(frames, LM.rHip, k7))
        if let tilt7 = angleFromVertical(sh, hp) {
            let E2 = events["E2"] ?? nil
            var series = [Double]()
            if let e2 = E2, let e7 = E7 {
                for k in 0..<t.count where t[k] >= e2 && t[k] <= e7 {
                    if let a = angleFromVertical(mid(pt(frames, LM.lShoulder, k), pt(frames, LM.rShoulder, k)),
                                                 mid(pt(frames, LM.lHip, k), pt(frames, LM.rHip, k))) {
                        series.append(a)
                    }
                }
            }
            let sd: Double? = series.count >= 3 ? std(series) : nil
            let rise: Double? = series.isEmpty ? nil : tilt7 - (series.reduce(0, +) / Double(series.count))
            let steady: Bool? = rise == nil ? nil : rise! <= 5.0
            var disp = "\(Int(tilt7.rounded()))°"
            if let s = steady { disp += s ? " · steady" : " · rising" }
            var m = FormMeasurement("spine_tilt", tilt7, "deg", 0.5, "best_effort",
                                    note: "torso angle from vertical at release (target 15–30°, steady). " + spineFwdNote,
                                    display: disp, id: "M2", viewRequired: "side")
            m.note = m.note   // consistency_sd/rise surfaced in extra on the server; kept in note here
            out["spine_tilt"] = m
        } else {
            out["spine_tilt"] = unavailPos("M2", "spine_tilt", "deg", "torso landmarks not visible at release", "side")
        }

        // M3 balance (off) arm abduction at release
        let offSh = pt(frames, si.offSh, k7)
        let offWr = pt(frames, si.offWr, k7)
        let down: (Double, Double)? = offSh.map { ($0.0, $0.1 + 0.2) }
        if let abd = angleBetween(offSh, offWr, down) {
            out["balance_arm"] = FormMeasurement("balance_arm", abd, "deg", 0.5, "best_effort",
                note: "off-arm abduction from the body at release (target ~90° out to the side)",
                display: "\(Int(abd.rounded()))° out", id: "M3", viewRequired: "front/rear")
        } else {
            out["balance_arm"] = unavailPos("M3", "balance_arm", "deg", "non-bowling arm not visible at release", "front/rear")
        }

        // M4 shoulder-line tilt at release
        let lsh = pt(frames, LM.lShoulder, k7)
        let rsh = pt(frames, LM.rShoulder, k7)
        if let stilt = angleFromHorizontal(lsh, rsh) {
            var bowlLower: Bool? = nil
            if let lsh, let rsh {
                let bowlingIsRight = !((handed ?? "R").trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("L"))
                let bowlY = bowlingIsRight ? rsh.1 : lsh.1
                let offY = bowlingIsRight ? lsh.1 : rsh.1
                bowlLower = bowlY > offY
            }
            var disp = "\(Int(abs(stilt).rounded()))°"
            if let b = bowlLower { disp += b ? " · bowling lower" : " · bowling higher" }
            out["shoulder_tilt"] = FormMeasurement("shoulder_tilt", abs(stilt), "deg", 0.5, "best_effort",
                note: "shoulder-line tilt at release (bowling shoulder slightly lower; chest rotation needs rear/overhead — not measured)",
                display: disp, id: "M4", viewRequired: "front/rear")
        } else {
            out["shoulder_tilt"] = unavailPos("M4", "shoulder_tilt", "deg", "shoulders not visible at release", "front/rear")
        }

        // M5 follow-through: bowling-wrist peak height vs head after release
        let holdEnd = events["hold_end"] ?? nil
        var m5disp: String? = nil
        var m5val: Double? = nil
        if let e7 = E7 {
            let hi = holdEnd ?? (e7 + 0.6)
            var best: (Double, Double)? = nil
            var headref: (Double, Double)? = nil
            for k in 0..<t.count where t[k] >= e7 && t[k] <= hi {
                guard let wr = pt(frames, si.bowlWr, k) else { continue }
                let nose = pt(frames, LM.nose, k)
                if best == nil || wr.1 < best!.1 { best = wr; headref = nose }
            }
            if let best, let headref, torso > 1e-6 {
                m5val = (headref.1 - best.1) / torso
                if m5val! >= 0.0 { m5disp = "Up to ear" }
                else if m5val! >= -0.5 { m5disp = "To shoulder" }
                else { m5disp = "Low" }
            }
        }
        if let m5disp {
            out["follow_through"] = FormMeasurement("follow_through", m5val, "ratio", 0.5, "best_effort",
                note: "bowling-wrist peak height vs head after release (\"answer the phone\"), torso lengths (+ above head)",
                display: m5disp, id: "M5", viewRequired: "side/front")
        } else {
            out["follow_through"] = unavailPos("M5", "follow_through", "ratio",
                "bowling wrist / head not visible through the follow-through", "side/front")
        }

        // M6 finish hold — surface the already-measured P1 value
        if let fh = metrics["finish_hold"], let v = fh.value, fh.status == "ok" || fh.status == "best_effort" {
            out["finish_hold"] = FormMeasurement("finish_hold", v, "s", fh.confidence, fh.status,
                note: "hold at the line after release (E8→E9); target is an owner setting (start ≥ 2.5 s ≈ ball travel time)",
                display: String(format: "%.1f s", v), id: "M6", viewRequired: "any")
        } else {
            out["finish_hold"] = unavailPos("M6", "finish_hold", "s", metrics["finish_hold"]?.note ?? "finish hold not measured", "any")
        }

        // M7 pendulum — proxy = downswing time
        if let dsw = metrics["downswing_time"], let v = dsw.value, dsw.status == "ok" || dsw.status == "best_effort" {
            out["pendulum"] = FormMeasurement("pendulum", v, "s", 0.4, "best_effort",
                note: "proxy only: downswing time vs your baseline and the T4 leverage window. No direct \"muscling\" metric from phone video.",
                display: String(format: "downswing %.2f s", v), id: "M7", viewRequired: "side")
        } else {
            out["pendulum"] = unavailPos("M7", "pendulum", "s", "downswing time not measured (needed for the pendulum proxy)", "side")
        }
        return out
    }

    private static func unavailPos(_ id: String, _ metric: String, _ unit: String, _ reason: String, _ vreq: String?) -> FormMeasurement {
        FormMeasurement(metric, nil, unit, 0.0, "unavailable", note: reason, display: "—", id: id, viewRequired: vreq)
    }
    private static func std(_ a: [Double]) -> Double {
        let m = a.reduce(0, +) / Double(a.count)
        let v = a.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(a.count)
        return v.squareRoot()
    }

    /// gate_positions(positions, view) — downgrade a position to unavailable when the view can't support it.
    static func gatePositions(_ positions: [String: FormMeasurement], view rawView: String) -> [String: FormMeasurement] {
        let view = allViews.contains(rawView) ? rawView : "unknown"
        var out = positions
        for (key, p) in positions {
            if p.status == "unavailable" { continue }
            guard let req = positionViews[key] else { continue }
            if view == "unknown" {
                if key == "spine_tilt" {
                    out[key] = unavailPos(p.id ?? "", key, p.unit, "forward spine tilt needs a confirmed side view", "side")
                } else {
                    var q = p
                    q.note = ((p.note ?? "") + " | capture view not confirmed — treat as provisional.")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " |"))
                    out[key] = q
                }
                continue
            }
            if !req.contains(view) {
                let label = p.viewRequired ?? (req.isEmpty ? "a different" : req.sorted().joined(separator: "/"))
                out[key] = unavailPos(p.id ?? "", key, p.unit, "needs a \(label) view (this clip is \(view))", p.viewRequired)
            }
        }
        return out
    }
}
