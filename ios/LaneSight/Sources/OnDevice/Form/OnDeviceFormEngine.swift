import Foundation

/// Top-level on-device Form analysis (DEC-129) — the Swift analogue of
/// `lanesight_core.form.pose.analyze` + `analyze_form_clip`. Ties the MediaPipe pose pass, the event/metric
/// engine, the ball-colour release confirmation and the fundamentals layer into one `FormAnalysis`.
///
/// This replaces the Apple-Vision `OnDeviceFormShadow` as the REAL on-device form measurer (full BlazePose feet).
/// It returns a completed record + per-stage report even when a stage can't produce its metric (DEC-122): swing
/// events that fail the honesty gate are withheld, but step count / approach duration / tempo still return.
nonisolated enum OnDeviceFormEngine {
    static let backendVersion = "ios-form-pose-0.1.0"   // mirrors pose.POSE_BACKEND_VERSION "form-pose-0.1.0"
    static let formVersion = "form-1.0.0"   // DEC-131: pose backend implemented (server + on-device parity)
    typealias LM = FormPoseLandmarker.LM

    /// Does a windowed pose pass actually contain the delivery AND yield swing events? Mirrors analyze's own
    /// delivery + swing-event logic so a too-tight prescan window (one that dropped the delivery) triggers the
    /// widen-to-full retry (decision 2: "widen and retry if events aren't found").
    private static func deliveryWithEventsFound(_ lms: FormPoseLandmarker.Landmarks, handed: String?) -> Bool {
        return deliveryProbe(lms, handed: handed).hasEvents
    }

    /// Quick delivery probe over an already-posed window: does any gated swing event survive, and how many foot
    /// plants are in the approach? Used both for the widen-to-full retry (no events) and the widen-the-lead retry
    /// (events but a truncated approach — step count < 3 because findDelivery anchored b0 late on a short lead).
    private static func deliveryProbe(_ lms: FormPoseLandmarker.Landmarks, handed: String?)
        -> (hasEvents: Bool, stepCount: Int) {
        let fr = lms.frames, tt = lms.t
        let rs = FormSignal.speed(FormSignal.point(fr, LM.rFootPts, axis: 0),
                                  FormSignal.point(fr, LM.rFootPts, axis: 1), tt)
        let ls = FormSignal.speed(FormSignal.point(fr, LM.lFootPts, axis: 0),
                                  FormSignal.point(fr, LM.lFootPts, axis: 1), tt)
        let slow = FormEngine.looksSlowmo(tt, fr, rs, ls)
        let delivery = slow
            ? FormEngine.findDelivery(tt, fr, rs, ls, burstMotion: 0.11, burstMaxS: 9.0, stillThr: 0.06)
            : FormEngine.findDelivery(tt, fr, rs, ls)
        guard let d = delivery else { return (false, 0) }
        let torso = FormSignal.torso(fr)
        let b0 = d.win.0 + 0.4
        let swingWin = (Swift.max(tt[0], b0 - 0.8), Swift.min(d.hold.0 + 0.3, tt[tt.count - 1]))
        let ev = FormEngine.swingEvents(tt, fr, ball: [:], win: swingWin, torso: torso)
        let hasEvents = ev.E4 != nil || ev.E6 != nil || ev.E7 != nil
        let relBound = (ev.E7 ?? d.hold.0) + 0.12
        let stepStart = FormEngine.setupHoldEnd(tt, rs, ls, burstStart: b0)
        let plants = FormEngine.footStrikes(tt, fr, win: (stepStart, relBound + 0.1), rs, ls)
            .filter { $0.0 >= stepStart && $0.0 <= relBound }
        return (hasEvents, plants.count)
    }

    /// Analyze a form clip end to end. `trackBall` runs the ball-colour release confirmation. It defaults OFF:
    /// on every labeled clip the reference's ball-confirm did NOT move E7 past the bottom of the arc (release_time
    /// stayed ~1 frame = E6+dt — see validation/form_ondevice_golden.json), so the wrist-arc release is
    /// parity-exact there and the expensive per-pixel tracker adds cost + a determinism risk for no gate benefit
    /// (FormBallTrack is a documented hook for a future clip that needs it).
    static func analyze(clipURL: URL, handed: String? = "right", modelPath: String? = nil,
                        bundle: Bundle = .main, trackBall: Bool = false) throws -> FormAnalysis {
        let lms = try extractWindowed(clipURL: clipURL, modelPath: modelPath, bundle: bundle, handed: handed)
        return analyze(landmarks: lms, handed: handed, clipURL: clipURL, trackBall: trackBall)
    }

    /// DEC-129 runtime + segmentation: find the dominant-motion delivery window with a cheap prescan and run pose
    /// ONLY there (+ margin); widen to the full clip and retry if the delivery burst isn't inside it. Split out so
    /// the gate can pose ONCE then run the (pure, deterministic) engine many times instead of re-posing 10×.
    static func extractWindowed(clipURL: URL, modelPath: String? = nil, bundle: Bundle = .main,
                                handed: String? = "right") throws -> FormPoseLandmarker.Landmarks {
        func ex(_ window: (Double, Double)?, windows: [(Double, Double)]? = nil,
                stride: Int = 1) throws -> FormPoseLandmarker.Landmarks {
            try FormPoseLandmarker.extract(clipURL: clipURL, modelPath: modelPath, bundle: bundle,
                                           window: window, windows: windows, poseStride: stride)
        }
        let lead = 1.6, tail = 0.9
        guard let bursts = FormPoseLandmarker.prescanBursts(clipURL: clipURL, top: 3), !bursts.isEmpty else {
            return try ex(nil)        // short clip / scan failed → pose the whole clip (DEC-129)
        }
        let windows = bursts.map { (Swift.max(0, $0.0 - lead), $0.1 + tail) }
        var winner = windows[0]       // default: the highest-energy burst (the old single-window prescan pick)
        if windows.count > 1 {
            // DEC-131 swing-aware prescan: coarse-pose (every 2nd frame) ALL top-N candidate windows in ONE pass,
            // then run the frozen selector (findDelivery) ONCE over the concatenated coarse landmarks. Scoring every
            // burst in a single pass makes the scores COMPARABLE across candidates (per-window scoring is NOT — a
            // far/small pre-shot or walk-back window inflates the shoulder-normalized swing in isolation, which
            // regressed 8847/8848), so a high-energy walk-back or pre-shot pacing can't out-rank the real delivery's
            // swing just by moving more. Full-rate pose then runs only on the winning burst's window. This fixes
            // IMG_8847 (was widening to the whole clip, ~43 s → now ~17 s window) and segments IMG_8825/8826/01:03
            // to the real delivery, staying under 30 s. Out-of-window gaps are dropped so they can't form spurious
            // bursts. Stride 2 (not 4): finer sampling is both affordable here and kinder to the thin-margin clips.
            let coarse = try ex(nil, windows: windows, stride: 2)
            let rs = FormSignal.speed(FormSignal.point(coarse.frames, LM.rFootPts, axis: 0),
                                      FormSignal.point(coarse.frames, LM.rFootPts, axis: 1), coarse.t)
            let ls = FormSignal.speed(FormSignal.point(coarse.frames, LM.lFootPts, axis: 0),
                                      FormSignal.point(coarse.frames, LM.lFootPts, axis: 1), coarse.t)
            if let d = FormEngine.findDelivery(coarse.t, coarse.frames, rs, ls) {
                let b0 = d.win.0 + 0.4, b1 = d.win.1 - 0.6     // recover the burst from the approach window
                winner = (Swift.max(0, b0 - lead), b1 + tail)
            }
            if ProcessInfo.processInfo.environment["FORM_PRESCAN_DBG"] != nil {
                let ws = windows.map { "[\(String(format: "%.1f", $0.0)),\(String(format: "%.1f", $0.1))]" }.joined(separator: " ")
                print("FORM_PRESCAN cands \(ws) -> winner [\(String(format: "%.1f", winner.0)),\(String(format: "%.1f", winner.1))]")
            }
        }
        var lms = try ex(winner)      // full-rate pose on the winning window
        let probe = Self.deliveryProbe(lms, handed: handed)
        if !probe.hasEvents {
            // The winner still didn't yield the delivery — widen to the FULL clip and retry (last resort, DEC-129).
            lms = try ex(nil)
        } else if probe.stepCount < 3 && winner.0 > 0.01 {
            // Events found but the approach came out truncated (< 3 plants): on a short lead findDelivery anchors b0
            // on the fast final steps and the step search misses the slow early steps, so step_count is banded
            // implausible (b6cfd17c: first_step 15.76, 2 steps on device vs 6 on the full clip). Re-pose with a
            // bigger lead so findDelivery has the context to anchor the whole approach; keep it only if it recovers
            // more steps and still finds the delivery. Fires only on the truncation case, so clean clips are
            // untouched. DEC-131.
            let wider = (Swift.max(0, winner.0 - 2.0), winner.1)
            let l2 = try ex(wider)
            let p2 = Self.deliveryProbe(l2, handed: handed)
            if p2.hasEvents && p2.stepCount > probe.stepCount { lms = l2 }
        }
        return lms
    }

    /// The PURE engine: events + metrics from already-extracted landmarks — no I/O, no randomness, deterministic.
    static func analyze(landmarks lms: FormPoseLandmarker.Landmarks, handed: String? = "right",
                        clipURL: URL? = nil, trackBall: Bool = false) -> FormAnalysis {
        let t = lms.t
        let frames = lms.frames
        let fps = lms.fps
        let frameS = 1.0 / fps
        let torso = FormSignal.torso(frames)

        // foot speeds over the whole clip
        let Rx = FormSignal.point(frames, LM.rFootPts, axis: 0)
        let Ry = FormSignal.point(frames, LM.rFootPts, axis: 1)
        let Lx = FormSignal.point(frames, LM.lFootPts, axis: 0)
        let Ly = FormSignal.point(frames, LM.lFootPts, axis: 1)
        let Rs = FormSignal.speed(Rx, Ry, t)
        let Ls = FormSignal.speed(Lx, Ly, t)

        let slowSuspect = FormEngine.looksSlowmo(t, frames, Rs, Ls)
        let delivery = slowSuspect
            ? FormEngine.findDelivery(t, frames, Rs, Ls, burstMotion: 0.11, burstMaxS: 9.0, stillThr: 0.06)
            : FormEngine.findDelivery(t, frames, Rs, Ls)

        let viewInfo = FormEngine.classifyViewFromPose(t, frames)

        guard let (approachWin, hold) = delivery else {
            return noDelivery(t: t, frames: frames, fps: fps, handed: handed, viewInfo: viewInfo,
                              reason: "could not isolate the delivery (no clear finish hold — pose likely failed on this clip, e.g. bowler too small or occluded; see FORM_ANALYSIS_SPEC §9).")
        }
        let (holdStart, holdEnd) = hold
        let b0 = approachWin.0 + 0.4

        // swing events (wrist arc; ball track confirms release)
        let swingWin = (Swift.max(t[0], b0 - 0.8), Swift.min(holdStart + 0.3, t[t.count - 1]))
        let ball: [Double: (Double, Double, Int)] = (trackBall && clipURL != nil)
            ? FormBallTrack.track(clipURL: clipURL!, t: t, frames: frames,
                                  t0: swingWin.0, t1: Swift.min(holdStart + 0.8, t[t.count - 1]))
            : [:]
        let ev = FormEngine.swingEvents(t, frames, ball: ball, win: swingWin, torso: torso)
        let E2 = ev.E2, E3 = ev.E3, E4 = ev.E4, E6 = ev.E6, E7 = ev.E7

        // foot plants
        let relBound = (E7 ?? holdStart) + 0.12
        let stepStart = FormEngine.setupHoldEnd(t, Rs, Ls, burstStart: b0)
        let strikes = FormEngine.footStrikes(t, frames, win: (stepStart, relBound + 0.1), Rs, Ls)
        let plants = strikes.filter { $0.0 >= stepStart && $0.0 <= relBound }.sorted { $0.0 < $1.0 }
        if plants.isEmpty {
            return noPlants(t: t, fps: fps, handed: handed, viewInfo: viewInfo,
                            events: ["E2": E2, "E3": E3, "E4": E4, "E6": E6, "E7": E7])
        }

        let strikeT = plants.map { $0.0 }
        var rawIntervals = [Double]()
        for i in 0..<(strikeT.count - 1) { rawIntervals.append(strikeT[i + 1] - strikeT[i]) }
        let slidePlant = strikeT[strikeT.count - 1]
        let firstStep = strikeT[0]

        // slide stop
        let sfAnchor = E6 ?? slidePlant
        let (slideFootLab, slideSpeedArr) = FormEngine.slideFoot(t, Rs, Ls, t0: sfAnchor - 0.3, t1: holdEnd, handed: handed)
        // E8 robust to a wrong/late anchor: the slide stop is ~0.3 s after the slide plant, never > SLIDE_MAX_S. The
        // bottom-of-arc E6 is fragile on a windowed on-device pose (DEC-131); when it's mis-detected late it pushes
        // the stop onto the trail-leg follow-through ~1.5 s later (8825/8826). Clamp the anchor toward the slide
        // plant + bound the search — a no-op on a clean clip (E6 ≈ plant + 0.3-0.4 s). Keep the foot/speed from the
        // original window so the slide-foot ID is unchanged.
        let stopAnchor = Swift.min(sfAnchor, slidePlant + 0.5)
        let stopTo = Swift.min(holdEnd, slidePlant + FormEngine.SLIDE_MAX_S)
        // When no clear rest is found (a mis-identified slide foot on a noisy on-device pose), the slide stop is
        // ~0.3 s after the slide plant — use that, NOT the posted-finish holdStart (~1.5 s later, the big 8825 E8
        // error). DEC-131.
        var slideStop = FormEngine.slideStop(t, slideSpeed: slideSpeedArr, anchor: stopAnchor, tTo: stopTo)
            ?? Swift.min(holdStart, slidePlant + 0.3)

        // E5 (slide START): slidePlant is a foot PLANT (a dip). When the SLIDE foot then slides — a clear speed peak
        // in the 0.3 s AFTER the plant that exceeds 2× its speed at the plant AND dominates the 0.3 s BEFORE it — the
        // labeled slide-start sits at that slide (~0.2 s later, e.g. IMG_8825). Snap E5 to the slide peak; it's a
        // no-op when the last plant is the post-slide settle (motion before dominates), so rear clips are unchanged.
        // slidePlant itself is kept for step timing, plant checks, and the E8 anchor. DEC-131.
        var slideStart = slidePlant
        let ssSmooth = FormSignal.smooth(FormSignal.nanToNum(slideSpeedArr, nan: 0.0), 3)
        var pkA = 0.0, pkB = 0.0, atPlant = 0.0, bestAftT = slidePlant
        var haveA = false, haveB = false
        for k in 0..<t.count {
            if t[k] >= slidePlant && t[k] <= slidePlant + 0.3 { haveA = true; if ssSmooth[k] > pkA { pkA = ssSmooth[k]; bestAftT = t[k] } }
            if t[k] >= slidePlant - 0.3 && t[k] < slidePlant { haveB = true; pkB = Swift.max(pkB, ssSmooth[k]) }
            if abs(t[k] - slidePlant) < 0.03 { atPlant = ssSmooth[k] }
        }
        if haveA && haveB && pkA > 2.0 * Swift.max(atPlant, 0.05) && pkA > pkB { slideStart = bestAftT }

        let rawFirstToRelease = E7.map { $0 - firstStep }
        var (isSlow, factor, slowNote) = FormEngine.detectSlowmo(stepIntervals: rawIntervals.map { Optional($0) },
                                                                 firstToRelease: rawFirstToRelease)
        var slowUncorrected = false
        var scale = 1.0
        if slowSuspect {
            isSlow = true; factor = 1; scale = 1.0; slowUncorrected = true
            slowNote = "slo-mo export DETECTED (clip \(Int((t[t.count - 1] - t[0]).rounded()))s with a playback-slowed interior). The delivery could NOT be reliably isolated or corrected on this clip: the slow backswing resembles a finish hold, the release blurs the pose, and the throw straddles the export speed ramp (non-uniform slowdown — no single factor applies). Values below are RAW file-time, UNCORRECTED."
        } else {
            scale = isSlow ? 1.0 / Double(factor) : 1.0
        }

        func dur(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, let b else { return nil }
            return (b - a) * scale
        }
        let intervals = rawIntervals.map { $0 * scale }
        let stepCount = strikeT.count
        let slideFoot = slideFootLab

        let pushaway = dur(E2, E3)
        let backswing = dur(E3, E4)
        let downswing = dur(E4, E6)
        let releaseTime = dur(E6, E7)
        let swingTime = dur(E2, E7)
        let approachTime = dur(firstStep, E7)
        let finishHold = (holdEnd - holdStart) * scale
        let ballHipToRelease = dur(E3, E7)
        let firstToRelease = dur(firstStep, E7)
        let tempo: Double? = (backswing != nil && downswing != nil && backswing! > 1e-6) ? downswing! / backswing! : nil

        // backswing height relative to shoulder
        var bhRel: Double? = nil
        if let e4 = E4, torso > 1e-6 {
            let k = FormSignal.argmin(t.map { abs($0 - e4) })
            let wy4 = Double(frames[k].lm[LM.rWrist][1])
            let s1 = Double(frames[k].lm[LM.lShoulder][1]), s2 = Double(frames[k].lm[LM.rShoulder][1])
            let sh4 = FormSignal.nanmean([s1, s2])
            if !wy4.isNaN && !sh4.isNaN { bhRel = (sh4 - wy4) / torso }
        }

        let unc = frameS * scale
        let be = "best_effort"
        let slowTag = slowUncorrected ? " [slo-mo: RAW/uncorrected]" : (isSlow ? " [slo-mo corrected \(factor)x]" : "")
        let swSrc = ev.src

        var metrics = [String: FormMeasurement]()
        metrics["step_count"] = FormMeasurement("step_count", Double(stepCount), "count", 0.4, be,
            note: "\(stepCount) foot plants (slide foot: \(slideFoot)) — APPROXIMATE (±1–2 steps); not yet validated to an exact count. Most reliable with both feet in frame for the whole approach (DEC-121)\(slowTag)")
        metrics["approach_time"] = FormMeasurement("approach_time", approachTime, "s", 0.6, be,
            note: "first foot plant -> release (E1 true start not reliable in rear view)\(slowTag)", uncertainty: 2 * unc)
        metrics["swing_time"] = FormMeasurement("swing_time", swingTime, "s",
            (E2 != nil && E7 != nil) ? 0.55 : 0.0, (E2 != nil && E7 != nil) ? be : "unavailable",
            note: "E2 ball-start -> E7 release, swing arc via \(swSrc)\(slowTag)", uncertainty: 2 * unc)
        metrics["pushaway_time"] = FormMeasurement("pushaway_time", pushaway, "s", pushaway != nil ? 0.4 : 0.0,
            pushaway != nil ? "low_confidence" : "unavailable",
            note: "E2->E3, hard to time in rear view (\(swSrc) arc)\(slowTag)", uncertainty: 2 * unc)
        metrics["backswing_time"] = FormMeasurement("backswing_time", backswing, "s", backswing != nil ? 0.6 : 0.0,
            backswing != nil ? be : "unavailable", note: "E3 ball-at-hip -> E4 apex (\(swSrc) arc)\(slowTag)", uncertainty: 2 * unc)
        metrics["downswing_time"] = FormMeasurement("downswing_time", downswing, "s", downswing != nil ? 0.65 : 0.0,
            downswing != nil ? be : "unavailable", note: "E4 apex -> E6 bottom of arc (\(swSrc) arc)\(slowTag)", uncertainty: unc)
        metrics["release_time"] = FormMeasurement("release_time", releaseTime, "s", releaseTime != nil ? 0.4 : 0.0,
            releaseTime != nil ? be : "unavailable",
            note: "E6 bottom of arc -> E7 release; the ball leaves at the bottom so this is ~1 frame unless the on-lane ball refines it (\(swSrc) arc)\(slowTag)", uncertainty: unc)
        var rhythm = FormMeasurement("rhythm_ratio", tempo, "ratio", tempo != nil ? 0.5 : 0.0,
            tempo != nil ? be : "unavailable", note: "swing tempo = downswing / backswing (ref session mean 0.51)")
        rhythm.display = FormEngine.rhythmDisplay(tempo)
        metrics["rhythm_ratio"] = rhythm
        metrics["finish_hold"] = FormMeasurement("finish_hold", finishHold, "s", 0.6, be,
            note: "both feet stationary = the posted finish hold, after the slide stop\(slowTag)", uncertainty: unc)
        var bh = FormMeasurement("backswing_height_rel", bhRel, "ratio", bhRel != nil ? 0.5 : 0.0,
            bhRel != nil ? be : "unavailable",
            note: "bowling-wrist apex vs shoulder line, torso lengths (+above/-below; ref \"about shoulder height\")")
        bh.display = FormEngine.backswingDisplay(bhRel)
        metrics["backswing_height_rel"] = bh

        // ball-start step index
        var bss: Int? = nil
        if let e2 = E2 {
            for i in 0..<strikeT.count {
                let lo = strikeT[i]
                let hi = i + 1 < strikeT.count ? strikeT[i + 1] : (E7 ?? (lo + 1))
                if lo <= e2 && e2 < hi { bss = i + 1; break }
            }
            if bss == nil && e2 < strikeT[0] { bss = 0 }
        }
        metrics["ball_start_step"] = FormMeasurement("ball_start_step", bss.map { Double($0) }, "index",
            bss != nil ? 0.4 : 0.0, bss != nil ? "low_confidence" : "unavailable",
            note: "step index containing E2 ball-start (0 = before the first tracked plant)")
        metrics["drift_boards"] = FormMeasurement("drift_boards", nil, "board", 0.0, "unavailable", note: FormEngine.calibReason)
        metrics["timing_at_slide"] = FormMeasurement("timing_at_slide", nil, "s", 0.0, "unavailable", note: FormEngine.validatingReason)
        metrics["slide_length"] = FormMeasurement("slide_length", nil, "inch", 0.0, "unavailable", note: FormEngine.validatingReason)

        // events (E5 = slide start; E8 = slide stop)
        var events: [String: Double?] = [
            "E2": E2, "E3": E3, "E4": E4, "E5": slideStart, "E6": E6, "E7": E7, "E8": slideStop,
            "first_step": firstStep, "slide_plant": slidePlant, "slide_stop": slideStop,
            "hold_start": holdStart, "hold_end": holdEnd,
        ]
        let (okEv, evReasons) = FormEngine.gateEvents(events)
        if !evReasons.isEmpty {
            for k in ["E2", "E3", "E4", "E6", "E7"] where !okEv.contains(k) { events[k] = Double?.none }
        }

        // measured positions from the GATED events
        let posEvents: [String: Double?] = [
            "E2": events["E2"] ?? nil, "E3": events["E3"] ?? nil, "E4": events["E4"] ?? nil, "E5": slideStart,
            "E6": events["E6"] ?? nil, "E7": events["E7"] ?? nil, "E8": slideStop,
            "first_step": firstStep, "slide_plant": slidePlant, "slide_stop": slideStop,
            "hold_start": holdStart, "hold_end": holdEnd,
        ]
        var positions = FormFundamentals.measuredPositions(t, frames, events: posEvents, torso: torso,
                                                           handed: handed, metrics: metrics)

        // slo-mo uncorrected downgrade
        if slowUncorrected {
            let warn = "SLO-MO (uncorrected): " + slowNote + " | "
            for (k, var m) in metrics where m.value != nil && m.status != "unavailable" {
                m.status = "low_confidence"
                m.note = warn + (m.note ?? "")
                metrics[k] = m
            }
        }

        // When the delivery couldn't be isolated (no gated swing event survived the DEC-095 gates), every
        // window-derived timing/count was measured off an unreliable window → withhold them all as unavailable +
        // FORM_DELIVERY_NOT_ISOLATED, never best_effort. The user sees "we couldn't time this", not a wrong number.
        // Parity with the server (pose.analyze). DEC-131.
        let gk = ["E2", "E3", "E4", "E6", "E7"].map { events[$0] ?? nil }
        let isoOk = gk.contains { $0 != nil }
        if !isoOk {
            let isoReason = "the delivery could not be isolated on this clip (no reliable swing events), so these "
                + "timings could not be measured — record with your full approach and swing in frame"
            for k in ["approach_time", "swing_time", "pushaway_time", "backswing_time", "downswing_time",
                      "release_time", "rhythm_ratio", "backswing_height_rel", "finish_hold", "step_count",
                      "ball_start_step", "timing_at_slide", "slide_length"] {
                guard let m = metrics[k], m.status != "unavailable" else { continue }
                var mm = FormMeasurement(k, nil, m.unit, 0.0, "unavailable", note: isoReason,
                                         id: m.id, viewRequired: m.viewRequired)
                mm.reasonCode = "FORM_DELIVERY_NOT_ISOLATED"
                metrics[k] = mm
            }
        }

        // DEC-131 plausibility backstop (runs LAST, overrides slo-mo too): a delivery timing/count outside its
        // physiological band is a mis-segmented delivery, not a real measurement → unavailable + IMPLAUSIBLE_VALUE,
        // never best_effort. Same bands as the server (failures._FORM_BANDS).
        for (k, m) in metrics {
            guard let v = m.value, let reason = FormEngine.implausibleReason(k, v) else { continue }
            var mm = FormMeasurement(k, nil, m.unit, 0.0, "unavailable", note: "implausible: " + reason,
                                     id: m.id, viewRequired: m.viewRequired)
            mm.reasonCode = "IMPLAUSIBLE_VALUE"
            metrics[k] = mm
        }

        // 2026-11-23 (Shayne's rear/side uploads): an impossible core timing means the DELIVERY was mis-segmented
        // (e.g. a whole approach found inside 0.4 s). Everything timed off that window is then wrong too — the
        // swing events (which drive the "Early/Late" checkpoints + thumbnails) and every swing-derived metric.
        // Withhold them all instead of showing "EARLY" verdicts built on a bad window. Zero plausible-but-wrong.
        let coreTiming = ["approach_time", "swing_time", "backswing_time", "downswing_time", "step_count"]
        let misSegmented = coreTiming.contains { metrics[$0]?.reasonCode == "IMPLAUSIBLE_VALUE" }
        if misSegmented {
            let why = "this delivery couldn't be timed reliably — record with your whole approach and swing in frame"
            for k in ["E2", "E3", "E4", "E6", "E7"] { events[k] = Double?.none }
            for k in ["pushaway_time", "backswing_time", "downswing_time", "release_time", "swing_time",
                      "rhythm_ratio", "backswing_height_rel", "ball_start_step", "approach_time", "step_count"] {
                guard let m = metrics[k], m.status != "unavailable" else { continue }
                var mm = FormMeasurement(k, nil, m.unit, 0.0, "unavailable", note: why,
                                         id: m.id, viewRequired: m.viewRequired)
                mm.reasonCode = "FORM_DELIVERY_NOT_ISOLATED"
                metrics[k] = mm
            }
        }
        // Positions were computed BEFORE the plausibility gate, so a rejected downswing still produced a pendulum
        // tile (0.05 s shown on the side clip). Rebuild them from the final events + metrics.
        positions = FormFundamentals.measuredPositions(t, frames, events: [
            "E2": events["E2"] ?? nil, "E3": events["E3"] ?? nil, "E4": events["E4"] ?? nil, "E5": slideStart,
            "E6": events["E6"] ?? nil, "E7": events["E7"] ?? nil, "E8": slideStop,
            "first_step": firstStep, "slide_plant": slidePlant, "slide_stop": slideStop,
            "hold_start": holdStart, "hold_end": holdEnd,
        ], torso: torso, handed: handed, metrics: metrics)

        // stage report (DEC-122)
        let isolated = isoOk && !misSegmented
        var stage: [String: FormStageOutcome] = [
            "decode": FormStageOutcome(status: "ok"),
            "pose": FormStageOutcome(status: "ok", frames: t.count),
            "swing_events": FormStageOutcome(status: isolated ? "ok" : "failed",
                                             reasonCode: isolated ? nil : "FORM_DELIVERY_NOT_ISOLATED",
                                             reason: isolated ? nil : (misSegmented ? "core timings implausible — delivery mis-segmented"
                                                                            : "every swing event failed the DEC-095 sanity gates")),
            "delivery_isolation": FormStageOutcome(status: isolated ? "ok" : "failed",
                                                   reasonCode: isolated ? nil : "FORM_DELIVERY_NOT_ISOLATED"),
            "slowmo": FormStageOutcome(status: "ok"),
        ]
        _ = intervals; _ = ballHipToRelease; _ = firstToRelease   // diagnostics parity (surfaced server-side)

        // analyze_form_clip layer: detected view + view gating of positions. Refine the view now the clean
        // approach window (firstStep → holdStart) is known — the full posed span alone mis-reads a real rear clip
        // as side when the bowler walked around a lot (DEC-131). Mirrors pose.analyze's re-classification.
        let refinedView = FormEngine.classifyViewFromPose(t, frames, approach: (firstStep, holdStart))
        let view = refinedView.view
        positions = FormFundamentals.gatePositions(positions, view: view)

        return FormAnalysis(
            formVersion: formVersion, view: view, viewInfo: refinedView, status: "ok", handed: handed, fps: fps,
            metrics: metrics, measuredPositions: positions, events: events, eventsGateReasons: evReasons,
            strikes: plants, stepIntervals: intervals, swingSource: swSrc,
            slowmo: (isSlow, factor, slowNote), stageReport: stage)
    }

    // MARK: early-return records (unavailable but completed — DEC-122)
    private static func allUnavailable(_ reason: String, fps: Double) -> [String: FormMeasurement] {
        var m = [String: FormMeasurement]()
        for (k, u) in FormAnalysis.p1Keys {
            let r = (k == "drift_boards") ? FormEngine.calibReason
                : (k == "timing_at_slide" || k == "slide_length") ? FormEngine.validatingReason : reason
            m[k] = FormMeasurement(k, nil, u, 0.0, "unavailable", note: r)
        }
        return m
    }

    private static func noDelivery(t: [Double], frames: [FormPoseLandmarker.Frame], fps: Double, handed: String?,
                                   viewInfo: (view: String, confidence: Double, reason: String), reason: String) -> FormAnalysis {
        let view = viewInfo.view
        let stage: [String: FormStageOutcome] = [
            "decode": FormStageOutcome(status: "ok"),
            "pose": FormStageOutcome(status: "ok", frames: t.count),
            "swing_events": FormStageOutcome(status: "failed", reasonCode: "FORM_DELIVERY_NOT_ISOLATED", reason: reason),
            "delivery_isolation": FormStageOutcome(status: "failed", reasonCode: "FORM_DELIVERY_NOT_ISOLATED", reason: reason),
        ]
        return FormAnalysis(formVersion: formVersion, view: view, viewInfo: viewInfo, status: "ok", handed: handed,
                            fps: fps, metrics: allUnavailable(reason, fps: fps), measuredPositions: [:],
                            events: [:], eventsGateReasons: [:], strikes: [], stepIntervals: [], swingSource: "wrist",
                            slowmo: (false, 1, ""), stageReport: stage)
    }

    private static func noPlants(t: [Double], fps: Double, handed: String?,
                                 viewInfo: (view: String, confidence: Double, reason: String),
                                 events: [String: Double?]) -> FormAnalysis {
        let reason = "delivery found but no foot plants detected in the approach window."
        let stage: [String: FormStageOutcome] = [
            "decode": FormStageOutcome(status: "ok"),
            "pose": FormStageOutcome(status: "ok", frames: t.count),
            "swing_events": FormStageOutcome(status: "failed", reasonCode: "FORM_DELIVERY_NOT_ISOLATED", reason: reason),
            "delivery_isolation": FormStageOutcome(status: "failed", reasonCode: "FORM_DELIVERY_NOT_ISOLATED"),
        ]
        return FormAnalysis(formVersion: formVersion, view: viewInfo.view, viewInfo: viewInfo, status: "ok",
                            handed: handed, fps: fps, metrics: allUnavailable(reason, fps: fps), measuredPositions: [:],
                            events: events, eventsGateReasons: [:], strikes: [], stepIntervals: [],
                            swingSource: "wrist", slowmo: (false, 1, ""), stageReport: stage)
    }
}
