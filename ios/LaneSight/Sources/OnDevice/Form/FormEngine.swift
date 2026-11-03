import Foundation

/// The on-device Form event + metric engine — a faithful port of `lanesight_core/form/pose.py::analyze` and its
/// helpers (`_find_delivery`, `_looks_slowmo`, `_setup_hold_end`, `_foot_strikes`, `_slide_foot`, `_slide_stop`,
/// `_swing_events`, `detect_slowmo`, `gate_events`) plus the FORM_P1 metric assembly.
///
/// Honesty rules (DEC-026/042/086): an unmeasurable metric is value=nil, status="unavailable", with the reason.
/// Partial results (DEC-122): the analysis always returns a completed record + per-stage report; swing-event /
/// delivery-isolation failure withholds the swing metrics but keeps step count / approach duration / tempo.
enum FormEngine {
    typealias Frame = FormPoseLandmarker.Frame
    typealias LM = FormPoseLandmarker.LM

    // tuning constants (pose.py)
    static let MIN_VIS = 0.3
    static let FINISH_HOLD_MIN_S = 0.45
    static let FOOT_STILL_FINISH = 0.16
    static let NOMINAL_APPROACH_S = 1.45
    static let PLAUSIBLE_STEP_MAX_S = 0.85
    static let SLOWMO_FACTORS = [2, 3, 4, 5, 6, 8]
    static let BURST_MOTION = 0.35
    static let BURST_MIN_S = 0.6
    static let BURST_MAX_S = 5.0
    static let FOOTVIS_MIN = 0.45
    static let SLIDE_STOP_SPEED = 0.12
    static let SLIDE_STOP_HOLD_S = 0.10
    static let RHYTHM_SPEEDS_UP_MAX = 0.85
    static let RHYTHM_SLOWS_DOWN_MIN = 1.15
    static let BACKSWING_ABOVE_MIN = 0.15
    static let BACKSWING_BELOW_MAX = -0.15
    static let RELEASE_VS_STOP_LO = -0.10, RELEASE_VS_STOP_HI = 0.15
    static let BALL_START_TO_RELEASE_LO = 1.3, BALL_START_TO_RELEASE_HI = 2.5

    static let calibReason = "needs floor-plane calibration — unresolved, see TRAINING_VIDEOS_CALIBRATED_METRICS addenda"
    static let validatingReason = "still being validated — ball-vs-slide timing / slide length need 120 fps "
        + "slide-and-release tracking that is not yet verified on this view (FORM_ANALYSIS_SPEC §9)"

    // MARK: delivery segmentation

    /// _find_delivery → (approachWin, (holdStart, holdEnd)) or nil.
    static func findDelivery(_ t: [Double], _ frames: [Frame], _ Rs: [Double], _ Ls: [Double],
                             burstMotion: Double = BURST_MOTION, burstMaxS: Double = BURST_MAX_S,
                             stillThr: Double = FOOT_STILL_FINISH) -> (win: (Double, Double), hold: (Double, Double))? {
        let n = t.count
        // footvis = mean visibility of [L_ANKLE,R_ANKLE,L_FOOT,R_FOOT]
        var footvis = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let r = frames[i].lm
            let vals = [r[LM.lAnkle][3], r[LM.rAnkle][3], r[LM.lFoot][3], r[LM.rFoot][3]].map { Double($0.isNaN ? 0 : $0) }
            footvis[i] = vals.reduce(0, +) / 4.0
        }
        let Ms = FormSignal.smooth(FormSignal.fmax(FormSignal.nanToNum(Rs, nan: 9.0), FormSignal.nanToNum(Ls, nan: 9.0)), 9)
        let hot = Ms.map { ($0.isNaN ? 0.0 : $0) > burstMotion }
        var bursts: [(Double, Double, Double)] = []
        var i = 0
        while i < n {
            if hot[i] {
                var j = i
                while j < n && hot[j] { j += 1 }
                let t0 = t[i], t1 = t[Swift.min(j - 1, n - 1)]
                if (t1 - t0) >= BURST_MIN_S && (t1 - t0) <= burstMaxS {
                    var sum = 0.0, c = 0
                    for k in 0..<n where t[k] >= t0 && t[k] <= t1 { sum += footvis[k]; c += 1 }
                    bursts.append((t0, t1, c > 0 ? sum / Double(c) : 0))
                }
                i = j
            } else { i += 1 }
        }
        let good = bursts.filter { $0.2 >= FOOTVIS_MIN }
        let pick: (Double, Double, Double)?
        if !good.isEmpty {
            pick = good.max { ($0.2 * Swift.min($0.1 - $0.0, 2.5)) < ($1.2 * Swift.min($1.1 - $1.0, 2.5)) }
        } else {
            pick = bursts.max { $0.2 < $1.2 }
        }
        guard let (b0, b1, _) = pick else { return nil }
        let approachWin = (Swift.max(t[0], b0 - 0.4), b1 + 0.6)
        // still = both feet below stillThr
        let Rf = FormSignal.nanToNum(Rs, nan: 9.0), Lf = FormSignal.nanToNum(Ls, nan: 9.0)
        var still = [Bool](repeating: false, count: n)
        for k in 0..<n { still[k] = Rf[k] < stillThr && Lf[k] < stillThr }
        var hold: (Double, Double)? = nil
        var idx = FormSignal.searchsorted(t, b1 - 0.4)
        while idx < n {
            if still[idx] {
                var j = idx
                while j < n && still[j] { j += 1 }
                if (t[Swift.min(j - 1, n - 1)] - t[idx]) >= FINISH_HOLD_MIN_S {
                    hold = (t[idx], t[Swift.min(j - 1, n - 1)]); break
                }
                idx = j
            } else { idx += 1 }
        }
        if hold == nil { hold = (b1, Swift.min(b1 + FINISH_HOLD_MIN_S, t[n - 1])) }
        return (approachWin, hold!)
    }

    /// _looks_slowmo → clip-level slo-mo cue.
    static func looksSlowmo(_ t: [Double], _ frames: [Frame], _ Rs: [Double], _ Ls: [Double]) -> Bool {
        let dur = t[t.count - 1] - t[0]
        if dur < 40.0 { return false }
        let n = t.count
        var present = [Bool](repeating: false, count: n)
        var pc = 0
        for i in 0..<n {
            let r = frames[i].lm
            let fv = [r[LM.lAnkle][3], r[LM.rAnkle][3], r[LM.lFoot][3], r[LM.rFoot][3]]
                .map { Double($0.isNaN ? 0 : $0) }.reduce(0, +) / 4.0
            present[i] = fv > 0.5
            if present[i] { pc += 1 }
        }
        if pc < 20 { return false }
        let M = FormSignal.fmax(FormSignal.nanToNum(Rs, nan: 0.0), FormSignal.nanToNum(Ls, nan: 0.0))
        var below = 0, tot = 0
        for i in 0..<n where present[i] { tot += 1; if M[i] < BURST_MOTION { below += 1 } }
        return tot > 0 && Double(below) / Double(tot) > 0.78
    }

    /// _setup_hold_end → where the first step begins (end of the setup stance).
    static func setupHoldEnd(_ t: [Double], _ Rs: [Double], _ Ls: [Double], burstStart: Double,
                             maxLookback: Double = 1.5, stillThr: Double = FOOT_STILL_FINISH,
                             minStillS: Double = 0.25) -> Double {
        let both = FormSignal.smooth(FormSignal.fmax(FormSignal.nanToNum(Rs, nan: 9.0), FormSignal.nanToNum(Ls, nan: 9.0)), 5)
        let still = both.map { $0 < stillThr }
        let dt = FormSignal.medianDiff(t)
        let need = Swift.max(1, Int((minStillS / dt).rounded()))
        let lo = Swift.max(t[0], burstStart - maxLookback)
        var i = Swift.min(FormSignal.searchsorted(t, burstStart), t.count - 1)
        while i > 0 && t[i] >= lo {
            if still[i] {
                var j = i
                while j > 0 && still[j] { j -= 1 }
                if (t[i] - t[j]) >= minStillS * 0.8 || (i - j) >= need {
                    return t[Swift.min(i + 1, t.count - 1)]
                }
                i = j
            } else { i -= 1 }
        }
        return burstStart - 0.4
    }

    /// _foot_strikes → chronological [(t, 'R'|'L')] foot plants inside the window.
    static func footStrikes(_ t: [Double], _ frames: [Frame], win: (Double, Double),
                            _ Rs: [Double], _ Ls: [Double]) -> [(Double, String)] {
        var idxs = [Int]()
        for i in 0..<t.count where t[i] >= win.0 && t[i] <= win.1 { idxs.append(i) }
        if idxs.isEmpty { return [] }
        let tt = idxs.map { t[$0] }
        let Rm = idxs.map { Rs[$0].isNaN ? 9.0 : Rs[$0] }
        let Lm = idxs.map { Ls[$0].isNaN ? 9.0 : Ls[$0] }
        let comb = FormSignal.smooth(FormSignal.fmax(Rm, Lm), 5)
        let mins = FormSignal.localMinima(comb, tt, sepS: 0.20, maxFrac: 0.65)
        var out = [(Double, String)]()
        for i in mins {
            let lab = Rm[i] <= Lm[i] ? "R" : "L"
            out.append((tt[i], lab))
        }
        return out
    }

    /// _slide_foot → ('L'|'R', slideFootSpeedArray) over [t0,t1].
    static func slideFoot(_ t: [Double], _ Rs: [Double], _ Ls: [Double], t0: Double, t1: Double,
                          handed: String?) -> (String, [Double]) {
        var idxs = [Int]()
        for i in 0..<t.count where t[i] >= t0 && t[i] <= t1 { idxs.append(i) }
        if idxs.isEmpty { idxs = Array(0..<t.count) }
        let Rm = idxs.map { Rs[$0].isNaN ? 9.0 : Rs[$0] }
        let Lm = idxs.map { Ls[$0].isNaN ? 9.0 : Ls[$0] }
        let rmean = Rm.reduce(0, +) / Double(Rm.count)
        let lmean = Lm.reduce(0, +) / Double(Lm.count)
        let foot: String
        if abs(rmean - lmean) < 0.08, let h = handed {
            foot = h.lowercased().hasPrefix("r") ? "L" : "R"
        } else {
            foot = lmean <= rmean ? "L" : "R"
        }
        return (foot, foot == "L" ? Ls : Rs)
    }

    /// _slide_stop → time the slide foot settles at the line, or nil.
    static func slideStop(_ t: [Double], slideSpeed: [Double], anchor: Double, tTo: Double,
                          thr: Double = SLIDE_STOP_SPEED, holdS: Double = SLIDE_STOP_HOLD_S) -> Double? {
        let sp = FormSignal.smooth(FormSignal.nanToNum(slideSpeed, nan: 9.0), 3)
        let lo = anchor - 0.6
        var idxs = [Int]()
        for i in 0..<t.count where t[i] >= lo && t[i] <= tTo { idxs.append(i) }
        if idxs.count < 2 { return nil }
        let dt = FormSignal.medianDiff(t)
        let hold = Swift.max(1, Int((holdS / dt).rounded()))
        // peak = argmax of sp over idxs
        var peak = idxs[0], pv = -Double.infinity
        for i in idxs where sp[i] > pv { pv = sp[i]; peak = i }
        for i in idxs {
            if i <= peak { continue }
            let j = Swift.min(t.count, i + hold + 1)
            if sp[i] < thr {
                let med = FormSignal.median(Array(sp[i..<j]))
                if med < thr { return t[i] }
            }
        }
        return nil
    }

    // MARK: swing events

    /// _swing_events → E2,E3,E4,E6,E7 from the bowling-wrist arc (ball track only confirms release).
    static func swingEvents(_ t: [Double], _ frames: [Frame], ball: [Double: (Double, Double, Int)],
                            win: (Double, Double), torso: Double)
        -> (E2: Double?, E3: Double?, E4: Double?, E6: Double?, E7: Double?, src: String, quality: String) {
        var mi = [Int]()
        for i in 0..<t.count where t[i] >= win.0 && t[i] <= win.1 { mi.append(i) }
        let tt = mi.map { t[$0] }
        let fail = (E2: Double?.none, E3: Double?.none, E4: Double?.none, E6: Double?.none,
                    E7: Double?.none, src: "wrist", quality: "low")
        if tt.count < 6 { return fail }
        var wyRaw = FormSignal.point(frames, [LM.rWrist], axis: 1)
        wyRaw = mi.map { wyRaw[$0] }
        let goodIdx = (0..<wyRaw.count).filter { !wyRaw[$0].isNaN }
        if goodIdx.count < 4 { return fail }
        var wy = FormSignal.interp(tt, goodIdx.map { tt[$0] }, goodIdx.map { wyRaw[$0] })
        wy = FormSignal.smooth(wy, 3)
        var hipRaw = FormSignal.point(frames, [LM.lHip, LM.rHip], axis: 1)
        hipRaw = mi.map { hipRaw[$0] }
        let gHip = (0..<hipRaw.count).filter { !hipRaw[$0].isNaN }
        let hipy: [Double] = gHip.isEmpty ? [Double](repeating: Double.nan, count: tt.count)
            : FormSignal.interp(tt, gHip.map { tt[$0] }, gHip.map { hipRaw[$0] })
        var bally = [Double](repeating: 0, count: tt.count)
        for i in 0..<tt.count { bally[i] = wy[i] + 0.45 * torso }
        let dt = FormSignal.median((1..<tt.count).map { tt[$0] - tt[$0 - 1] })
        let span = tt[tt.count - 1] - tt[0]
        let (mx, mn) = FormSignal.localExtrema(wy, tt, sepS: 0.18)
        let late = mn.filter { tt[$0] > tt[0] + 0.55 * span }
        let pr: Int = late.isEmpty ? FormSignal.argmin(wy) : (late.min { wy[$0] < wy[$1] } ?? FormSignal.argmin(wy))
        let beforeMax = mx.filter { $0 < pr }
        let i6 = beforeMax.last ?? FormSignal.argmax(wy)
        let E6 = tt[i6]
        let beforeMin = mn.filter { $0 < i6 }
        let i4: Int = beforeMin.last ?? FormSignal.argmin(Array(wy[0...i6]))
        let E4 = tt[i4]
        let v = FormSignal.gradient(wy, tt)
        // vthr = max(0.05, 0.30 * nanmax(|v[tt<=E6]|))
        let preAbs = (0..<tt.count).filter { tt[$0] <= E6 }.map { abs(v[$0]) }
        let vthr = preAbs.isEmpty ? 0.25 : Swift.max(0.05, 0.30 * (FormSignal.nanmax(preAbs)))
        var E2: Double? = nil
        for k in 0..<tt.count {
            if tt[k] >= E4 { break }
            if abs(v[k]) > vthr { E2 = tt[k]; break }
        }
        var E3 = E2
        if !gHip.isEmpty {
            var k = i4
            while k > 0 {
                if let e2 = E2, tt[k] < e2 { break }
                if bally[k] >= hipy[k] && bally[k - 1] < hipy[k - 1] { E3 = tt[k]; break }
                k -= 1
            }
        }
        var E7 = E6 + dt
        // ball confirmation of release
        if !ball.isEmpty {
            let bt = ball.keys.sorted()
            let by = bt.map { ball[$0]!.1 }
            let after = (0..<bt.count).filter { bt[$0] >= E6 - dt }
            for k in after.dropLast(3) {
                if k + 4 <= by.count {
                    let seg = Array(by[k..<(k + 4)])
                    var receding = true
                    for s in 1..<4 where !(seg[s] - seg[s - 1] < 0.0) { receding = false }
                    if receding {
                        if bt[k] <= E6 + 3 * dt { E7 = Swift.max(E7, bt[k]) }
                        break
                    }
                }
            }
        }
        return (E2, E3, E4, E6, E7, "wrist", E3 == E2 ? "best_effort" : "ok")
    }

    // MARK: slo-mo

    /// detect_slowmo → (isSlowmo, factor, note).
    static func detectSlowmo(stepIntervals: [Double?], firstToRelease: Double?) -> (Bool, Int, String) {
        let ivals = stepIntervals.compactMap { $0 }
        let med: Double? = ivals.isEmpty ? nil : FormSignal.median(ivals)
        let slow = (med != nil && med! > PLAUSIBLE_STEP_MAX_S) || (firstToRelease != nil && firstToRelease! > 2.6)
        if !slow { return (false, 1, "") }
        let raw: Double = (firstToRelease != nil && firstToRelease! > 0) ? firstToRelease! / NOMINAL_APPROACH_S
            : (med ?? 0.45) / 0.45
        let factor = SLOWMO_FACTORS.min { abs(Double($0) - raw) < abs(Double($1) - raw) } ?? 1
        let note = "slo-mo export detected: raw cadence ~\(String(format: "%.1f", raw))x physiological; corrected by "
            + "\(factor)x (captured ~\(Int(30 * factor)) fps, saved at 30 fps). Single-clip detection — no capture-fps "
            + "metadata present; factor snapped to the nearest iPhone slo-mo ratio."
        return (true, factor, note)
    }

    // MARK: honesty gate

    /// gate_events → (okSet, reasons). Mirrors pose.gate_events exactly.
    static func gateEvents(_ ev: [String: Double?]) -> (ok: Set<String>, reasons: [String: String]) {
        let disp = ["E2", "E3", "E4", "E6", "E7"]
        var ok = Set(disp.filter { (ev[$0] ?? nil) != nil })
        var reasons = [String: String]()
        func drop(_ keys: [String], _ why: String) {
            for k in keys where ok.contains(k) { ok.remove(k); reasons[k] = why }
        }
        let E2 = ev["E2"] ?? nil, E6 = ev["E6"] ?? nil, E7 = ev["E7"] ?? nil
        _ = E6
        let stop = ev["E8"] ?? nil
        if let e7 = E7, let s = stop, !(s + RELEASE_VS_STOP_LO <= e7 && e7 <= s + RELEASE_VS_STOP_HI) {
            drop(disp, "release (\(String(format: "%.2f", e7))s) isn't near the slide stop (\(String(format: "%.2f", s))s) — off by \(String(format: "%+.2f", e7 - s))s, so the delivery couldn't be timed reliably on this clip.")
            return (ok, reasons)
        }
        if let e2 = E2, let e7 = E7 {
            let d = e7 - e2
            if !(BALL_START_TO_RELEASE_LO <= d && d <= BALL_START_TO_RELEASE_HI) {
                drop(["E2", "E3"], "ball start → release measured \(String(format: "%.2f", d))s (a real delivery is \(fmtg(BALL_START_TO_RELEASE_LO))–\(fmtg(BALL_START_TO_RELEASE_HI))s), so ball start is unreliable.")
            }
        }
        // monotonic order among survivors
        let order = disp.filter { ok.contains($0) && (ev[$0] ?? nil) != nil }.map { ($0, ev[$0]!!) }
        for i in 1..<Swift.max(order.count, 1) where order.count >= 2 {
            let (k0, v0) = order[i - 1], (k1, v1) = order[i]
            if v1 < v0 - 1e-3 {
                drop([k1], "\(k1) (\(String(format: "%.2f", v1))s) comes before \(k0) (\(String(format: "%.2f", v0))s) — the events are out of order.")
            }
        }
        return (ok, reasons)
    }
    private static func fmtg(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(x)
    }

    // MARK: read-outs
    static func rhythmDisplay(_ ratio: Double?) -> String? {
        guard let r = ratio else { return nil }
        if r <= RHYTHM_SPEEDS_UP_MAX { return "Speeds up" }
        if r >= RHYTHM_SLOWS_DOWN_MIN { return "Slows down" }
        return "Even"
    }
    static func backswingDisplay(_ rel: Double?) -> String? {
        guard let r = rel else { return nil }
        if r >= BACKSWING_ABOVE_MIN { return "Above shoulder" }
        if r <= BACKSWING_BELOW_MAX { return "Below shoulder" }
        return "Shoulder"
    }

    /// classify_view_from_pose → {view, confidence, reason} (MVP-03).
    static func classifyViewFromPose(_ t: [Double], _ frames: [Frame]) -> (view: String, confidence: Double, reason: String) {
        var okMask = [Bool](repeating: false, count: frames.count)
        var okCount = 0
        for i in 0..<frames.count {
            let r = frames[i].lm
            let ok = Double(r[LM.lShoulder][3]) > MIN_VIS && Double(r[LM.rShoulder][3]) > MIN_VIS
                && Double(r[LM.lHip][3]) > MIN_VIS && Double(r[LM.rHip][3]) > MIN_VIS
            okMask[i] = ok; if ok { okCount += 1 }
        }
        if okCount < 8 { return ("unknown", 0.0, "Not enough clear pose frames to tell the camera view.") }
        var hipX = [Double](), hipY = [Double]()
        for i in 0..<frames.count where okMask[i] {
            let r = frames[i].lm
            hipX.append((Double(r[LM.lHip][0]) + Double(r[LM.rHip][0])) / 2)
            hipY.append((Double(r[LM.lHip][1]) + Double(r[LM.rHip][1])) / 2)
        }
        let dx = FormSignal.nanmax(hipX) - FormSignal.nanmin(hipX)
        let dy = FormSignal.nanmax(hipY) - FormSignal.nanmin(hipY)
        if Swift.max(dx, dy) < 0.08 {
            return ("unknown", 0.1, "The bowler barely moves in frame — the camera view is unclear (check framing).")
        }
        let frac = Double(okCount) / Double(frames.count)
        if dy / Swift.max(dx, 1e-3) < 0.30 {
            return ("down_lane", round2(0.5 + 0.2 * frac), "The bowler moves across the frame — a side (profile) view.")
        }
        return ("rear", round2(0.4 + 0.2 * frac), "The bowler moves up the frame toward the pins — a rear view.")
    }
    static func round2(_ x: Double) -> Double { ((x * 100).rounded()) / 100 }
}
