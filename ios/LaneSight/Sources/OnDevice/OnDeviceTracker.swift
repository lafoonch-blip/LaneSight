import Foundation
import AVFoundation
import CoreVideo
import simd

// DEC-102/103 — Phase 3, stage 3 (SHADOW, FIRST PASS). On-device ball detection + tracking, ported from
// lanesight_core/cv/track.py (extract_blobs → candidates → link). Produces a ball track in image space:
// one (t, cx, contact_row, lateral-fraction) per frame.
//
// FIRST PASS scope: background = per-pixel median of sampled frames (no per-frame homography warp — valid for
// tripod/stabilized clips, the common case; handheld warp is the server's job and a later brick). Diff →
// threshold → morphology → connected components (union-find) → diameter-gated candidates (using the stage-2
// lane geometry) → RANSAC trajectory link. SHADOW: never shown/counted. Run from the dev panel; eyeball the
// track on real clips — thresholds (diff/area/diameter) are the tuning levers.

struct TrackPoint: Equatable { let i: Int; let t: Double; let cx: Float; let contactRow: Float; let frac: Float }

/// First end-to-end metric. ball_speed = 60 ft / (t_impact − t_release) (cv/metrics.py headline). t_release =
/// foul-line crossing − 0.068 s learned offset; t_impact approximated by the last track point (the ball nearest
/// the pins) — labeled best_effort because true impact needs pin-motion detection (next brick). entryFrac is
/// the lateral fraction at the last point (0 = left edge, 1 = right edge) → maps to board with calibration.
struct SpeedEstimate: Equatable {
    let mph: Float?
    let tRelease: Double?
    let tImpact: Double?
    let entryFrac: Float?
    let basis: String          // "best_effort" | "unavailable"
    let note: String
    var avgFoulToPinsMph: Float? = nil   // DEC-064/DEC-112 full-lane average = 59.44 ft / (tImpact − tFoulCross),
                                         // the TRUTH-comparable metric (matches Shayne's foul→pin labels)
    var tFoulCross: Double? = nil
}
struct BallTrack: Equatable {
    let points: [TrackPoint]
    let framesScanned: Int
    let candidateFrames: Int
    let seconds: Double
    var impactT: Double? = nil          // detected pin-deck arrival time (preferred t_impact)
    var foulCrossOverride: Double? = nil  // DEC-132: robust bracket-interpolated foul time (learned track); if set,
                                          // speed() uses it instead of the global-fit foul (small-ball noise skews it)
    // DEC-128 port-parity diagnostics (compared against the server dump to find where the Swift port diverges).
    var thrEff: Int = 0
    var bgLevel: Float = 0
    var totalBlobs: Int = 0
    var framesWithBlobs: Int = 0
    var totalCandidates: Int = 0
    var bgLumaMean: Float = 0           // mean of the working-res max-channel background plate (decode-level check)
    var gateReject: String = ""         // per-gate rejection counts (which gate kills the ball candidates)
    var selectedLane: ODDetectedLane? = nil   // DEC-128: the lane the ball was found on (boards must use THIS lane)
    var laneFromFallback: Bool = false  // DEC-128: ball found on a raw/pale-lane fallback (not a VP-validated lane)
                                        // → its unrefined geometry makes every board read off it best_effort
    nonisolated var spanFrac: Float { (points.first.map { p in (points.last!.frac - p.frac) }) ?? 0 }
}

// Physical constants (match cv/track.py / lane_geometry).
private nonisolated(unsafe) let BALL_IN: Float = 8.5
private nonisolated(unsafe) let LANE_IN: Float = 41.5

// Brightness-RELATIVE foreground threshold (DEC-117 robustness; mirrors cv/track.py THR_L_NOMINAL). The bg-diff
// scales with any global gain the decode applies, so a fixed absolute threshold segments a brighter/darker copy
// of the same clip differently → the ball track tail and the speed anchor move. Scaling the threshold by the
// clip's own background level makes it gain-invariant, so the iOS AVFoundation decode can't recreate the
// platform speed gap the server hit. L_NOMINAL ≈ the IMG_8751-54 mean working-luma level (max-channel basis,
// same as downsampledLuma); bounds guard pathological lanes.
private nonisolated(unsafe) let THR_L_NOMINAL: Float = 165
private nonisolated(unsafe) let THR_MIN: Float = 25
private nonisolated(unsafe) let THR_MAX: Float = 55

enum OnDeviceTracker {

    // DEC-132 coverage diag: detectImpact records WHY it returned (withhold reason or the accepted path), surfaced
    // in the shadow diag so the 22-clip gate shows the exact impact-stage blocker per clip. Debug-only; no behavior.
    nonisolated(unsafe) static var lastImpactDebug: String = ""

    // geometry helpers (ports of track.py exp_diam / contact_row; lane_x from the stage-2 edges)
    nonisolated private static func laneX(_ l: ODDetectedLane, _ y: Float) -> (Float, Float) {
        (l.left.a * y + l.left.b, l.right.a * y + l.right.b)
    }
    nonisolated private static func expDiam(_ l: ODDetectedLane, _ y: Float) -> Float {
        let (xa, xb) = laneX(l, y); return BALL_IN / LANE_IN * (xb - xa)
    }
    nonisolated private static func contactRow(_ l: ODDetectedLane, top: Float) -> Float {
        let k = BALL_IN / LANE_IN
        return (top + k * (l.right.b - l.left.b)) / (1 - k * (l.right.a - l.left.a))
    }

    /// Ball speed = 60 ft / (t_impact − t_release). Instead of taking the last track point (which overshoots
    /// into the pit), fit the ball's u(t)=1/(ct−vpY) line and extrapolate it to the FOUL line and the lane's
    /// FAR extent (≈ pin deck) — t at each anchor. This excludes the post-impact tail. best_effort until a
    /// real pin-impact detector + arrow/pin distance anchor land (then "60 ft" and t_impact become exact).
    nonisolated static func speed(track: BallTrack, geo: ODLaneGeometry) -> SpeedEstimate {
        func fail(_ m: String) -> SpeedEstimate { SpeedEstimate(mph: nil, tRelease: nil, tImpact: nil, entryFrac: track.points.last?.frac, basis: "unavailable", note: m) }
        let pts = track.points.sorted { $0.t < $1.t }
        guard pts.count >= 6, let foulY = geo.foulLineY, let vp = geo.vanishingPoint, let lane = geo.lanes.first else {
            return fail("need ≥6 track points + lane geometry (foul line, VP, lane)")
        }
        let vpY = vp.y
        // DEC-132: degenerate-geometry guard. A collapsed/ill-conditioned lane solve puts the vanishing point far off
        // frame (IMG_8753 on device: VP (-30010, -141764)); the u(t) depth fit through it is garbage and the speed is
        // meaningless (read 13.2 for an 18.3 mph ball). Withhold — the device can't do this clip's geometry (the server
        // only recovers 8753 via stabilized frames). Legit VPs sit within a few frame-heights of the image.
        guard abs(vp.x) < 6000, abs(vpY) < 6000 else { return fail("degenerate lane geometry — vanishing point off-frame (\(Int(vp.x)),\(Int(vpY)))") }
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        // least-squares u = slope*t + intc over the track
        var n = 0.0, st = 0.0, su = 0.0, stt = 0.0, stu = 0.0
        for p in pts { let t = Double(p.t), uu = Double(u(p.contactRow)); n += 1; st += t; su += uu; stt += t * t; stu += t * uu }
        let den = n * stt - st * st
        guard abs(den) > 1e-9 else { return fail("degenerate trajectory fit") }
        let slope = (n * stu - st * su) / den
        let intc = (su - slope * st) / n
        guard slope > 0 else { return fail("non-monotonic track (ball not clearly moving toward the pins)") }
        let tFoulCross = track.foulCrossOverride ?? ((Double(u(Float(foulY))) - intc) / slope)   // ball crosses the foul line
        // t_impact = ball-at-pins ("ball centre at first head-pin contact"). Use the pin-deck MOTION detector
        // (track.impactT), which marks the pin location directly, MINUS the pin-fall latency: a struck pin takes
        // ~0.15 s to move visibly, so the motion spike lags ball-contact by that much (measured +0.17/+0.18 s on
        // 8751/8754). The lane far extent is NOT the pin row (the ball tracks past it; the true pin depth needs the
        // gated metric plane), so a trajectory extrapolation undershoots — only used as a fallback when no spike.
        // t_impact = ball-at-pins, from the pin-deck MOTION detector (track.impactT). WITHHOLD when it is nil —
        // server parity (analyze_learned returns PIN_IMPACT_NOT_DETECTED; detect_impact → None when no sustained pin
        // motion). The former far-down-lane fallback (tImpact = argmax(u)) FABRICATED an impact and produced a
        // plausible-but-wrong foul→pins speed on EVERY clip the server withholds — the validation set is unambiguous:
        // measured impact → correct (8751/8752/8966/8967), no measured impact → wrong (8963/8964/8968/8970/8972/
        // 8973/8974/8978). No correct clip relied on the fallback, so it is pure over-production. No fabricated impact.
        guard let tImpact = track.impactT else {
            return fail("pin contact not detected — no pin-deck motion changepoint (PIN_IMPACT_NOT_DETECTED); speed unavailable")
        }
        let release = tFoulCross - 0.068                              // RELEASE_OFFSET_S (cv/metrics.py)
        let dt = tImpact - release
        guard dt > 0.5 && dt < 5 else { return fail("implausible foul→impact interval (\(String(format: "%.2f", dt))s)") }
        let mph = Float(60.0 / dt * 3600.0 / 5280.0)
        guard mph > 5 && mph < 30 else { return fail("speed out of range (\(String(format: "%.1f", mph)) mph) — track likely short of the pins") }
        // DEC-064/DEC-112 full-lane average = 59.44 ft / (tImpact − tFoulCross): the TRUTH-comparable number
        // (same interval the foul_cross→first_pin_contact labels measure), impact anchored to the ball at the pins.
        let Z_IMPACT = 59.44
        let dtAvg = tImpact - tFoulCross
        // DEC-122 step 7b honesty gate (server parity, cv/pipeline.py _foul_observed): the foul→pins speed needs
        // the ball tracked NEAR the foul line, not extrapolated from mid-lane. Distance from the foul to the FIRST
        // tracked point = avg speed × (t_first − t_foul). If the ball was first seen > 6 ft downlane the foul
        // crossing is extrapolated → withhold the speed (unavailable + reason), exactly like the server withholds
        // IMG_8970 / IMG_8969. No fabricated number.
        let firstObservedFt = (dtAvg > 0.1) ? Float(Z_IMPACT / dtAvg) * Float(pts[0].t - tFoulCross) : 999
        guard firstObservedFt <= 6.0 else {
            return fail("foul crossing extrapolated: the ball was first tracked \(String(format: "%.1f", firstObservedFt)) ft downlane (needs ≤ 6 ft) — speed unavailable (DEC-122 7b)")
        }
        let avg: Float? = (dtAvg > 0.5 && dtAvg < 5) ? Float(Z_IMPACT / dtAvg * 3600.0 / 5280.0) : nil
        return SpeedEstimate(mph: mph, tRelease: release, tImpact: tImpact, entryFrac: pts.last!.frac, basis: "best_effort",
                             note: "best_effort: trajectory anchors (foul crossing + ball at the lane far extent); foul observed \(String(format: "%.1f", firstObservedFt)) ft",
                             avgFoulToPinsMph: avg, tFoulCross: tFoulCross)
    }

    /// Per-lane run of the blob→candidate→link chain + its ball score.
    private struct LaneRun { var lane: ODDetectedLane; var pts: [TrackPoint]; var perFrame: [[Cand]]
                             var scanned: Int; var thrEff: Int; var bgLevel: Float
                             var totalBlobs: Int; var framesWithBlobs: Int
                             var rej: (Int, Int, Int, Int, Int); var score: Float }

    /// Port of cv/pipeline.py `_lane_ball_score`: how much a lane's linked track looks like the lane the BALL
    /// rolled down — many points, lateral position staying within the (padded) edges, travelling downlane. Empty
    /// / wrong lanes score 0. This is the selection signal (never lanes.first) — DEC-128.
    nonisolated private static func laneBallScore(_ pts: [TrackPoint], vpY: Float) -> Float {
        if pts.count < 5 { return 0 }
        let inLane = Float(pts.filter { $0.frac > -0.15 && $0.frac < 1.15 }.count) / Float(pts.count)
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        let span = u(pts.last!.contactRow) - u(pts.first!.contactRow)   // pts sorted by t
        if inLane < 0.5 || span <= 0 { return 0 }
        return Float(pts.count) * inLane * span
    }

    nonisolated static func track(url: URL, geo: ODLaneGeometry, diffThr: Int = 35,
                                  maxBgFrames: Int = 12, rot: ODRotation = .r0) -> BallTrack {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let vp = geo.vanishingPoint,
              let (sw, sh, stride, ts, bg) = buildBackground(url: url, maxFrames: maxBgFrames, rot: rot) else {
            return BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        let vpY = vp.y
        let s = Float(stride)
        // Run the full blob→candidate→link chain for ONE lane (threshold + candidates are lane-dependent, so this
        // decodes once per lane, like the server's per-lane extract_blobs).
        func runLane(_ lane: ODDetectedLane, useMerge: Bool) -> LaneRun {
            let foulY = Float(geo.foulLineY ?? Int(lane.yNear))
            let bgLevel = laneBgLevel(bg: bg, sw: sw, sh: sh, lane: lane, stride: stride, vpY: vpY, foulY: foulY)
            let thrEff = Int(min(THR_MAX, max(THR_MIN, Float(diffThr) * bgLevel / THR_L_NOMINAL)).rounded())
            var perFrame: [[Cand]] = []
            var scanned = 0, totalBlobs = 0, framesWithBlobs = 0
            var rejD = 0, rejVert = 0, rejShape = 0, rejFrac = 0, passed = 0
            forEachLuma(url: url, stride: stride, sw: sw, sh: sh, rot: rot) { i, luma in
                scanned += 1
                let blobs = foregroundBlobs(luma: luma, bg: bg, w: sw, h: sh, thr: thrEff)
                totalBlobs += blobs.count
                if !blobs.isEmpty { framesWithBlobs += 1 }
                let raw: [FBlob] = blobs.map { FBlob(x: Float($0.x) * s, y: Float($0.y) * s,
                                                     w: Float($0.w) * s, h: Float($0.h) * s, a: Float($0.area) * s * s) }
                var cs: [Cand] = []
                // Gate raw blobs, PLUS merged fragment groups (ports cv/track.py candidates()) ONLY on the raw-lane
                // fallback path: the ball fragments on a glare/low-contrast (pale) lane, and without the merge each
                // fragment fails the width/area gate (the 80ae104f pale lane). The good-lane path keeps the exact
                // original candidate set so the validated clips (IMG_8751-54) are byte-unchanged (DEC-128).
                let cands = useMerge ? raw + ballFragmentGroups(raw, lane: lane) : raw
                for b in cands {
                    let bx = b.x, by = b.y, bw = b.w, bh = b.h, ba = b.a
                    let ct = contactRow(lane, top: by)
                    let D = expDiam(lane, ct)
                    if D < 8 { rejD += 1; continue }
                    if ct > foulY + 40 || ct < vpY + 10 { rejVert += 1; continue }
                    let ratio = bw / D
                    if ratio > 0.7 && ratio < 1.35 && bh < 3.2 * D && ba > 0.25 * D * D {
                        let (xa, xb) = laneX(lane, ct)
                        let cx = bx + bw / 2
                        let frac = (cx - xa) / (xb - xa)
                        if frac < -0.05 || frac > 1.05 { rejFrac += 1; continue }
                        passed += 1
                        cs.append(Cand(i: i, t: i < ts.count ? ts[i] : (ts.last ?? 0), cx: cx, ct: ct, frac: frac))
                    } else { rejShape += 1 }
                }
                perFrame.append(cs)
            }
            let pts = ransacLink(perFrame, vpY: vpY)
            return LaneRun(lane: lane, pts: pts, perFrame: perFrame, scanned: scanned, thrEff: thrEff,
                           bgLevel: bgLevel, totalBlobs: totalBlobs, framesWithBlobs: framesWithBlobs,
                           rej: (rejD, rejVert, rejShape, rejFrac, passed), score: laneBallScore(pts, vpY: vpY))
        }
        // DEC-128 lane selection: the server runs every detected lane and keeps the one the BALL rolled down
        // (_lane_ball_score), never lanes.first. Try the VP-consistent (refined) good lanes first; if the ball is
        // on none of them (a pale lane whose edges skewed the shared VP got dropped from `good`), fall back to the
        // raw lanes — the real lane is still there and the ball scores highest on it.
        func bestOver(_ list: [ODDetectedLane], useMerge: Bool) -> LaneRun? {
            var best: LaneRun? = nil
            for lane in list {
                let r = runLane(lane, useMerge: useMerge)
                if best == nil || r.score > best!.score { best = r }
            }
            return best
        }
        var best = bestOver(geo.lanes, useMerge: false)   // good lanes: exact original candidate set (golden-safe)
        var fromFallback = false
        if (best?.score ?? 0) <= 0, !geo.rawLanes.isEmpty,            // ball on no good lane → pale-lane fallback:
           let rawBest = bestOver(geo.rawLanes, useMerge: true),      // raw lanes + fragment merge to recover it
           rawBest.score > (best?.score ?? 0) {
            best = rawBest; fromFallback = true                        // boards read off this lane are best_effort
        }
        guard let b = best else {
            return BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        let candFrames = b.perFrame.filter { !$0.isEmpty }.count
        var result = BallTrack(points: b.pts, framesScanned: b.scanned, candidateFrames: candFrames,
                               seconds: CFAbsoluteTimeGetCurrent() - t0)
        result.thrEff = b.thrEff
        result.bgLevel = b.bgLevel
        result.totalBlobs = b.totalBlobs
        result.framesWithBlobs = b.framesWithBlobs
        result.totalCandidates = b.perFrame.reduce(0) { $0 + $1.count }
        if !bg.isEmpty { result.bgLumaMean = Float(bg.reduce(0) { $0 + Int($1) }) / Float(bg.count) }
        result.gateReject = "D:\(b.rej.0) vert:\(b.rej.1) shape:\(b.rej.2) frac:\(b.rej.3) pass:\(b.rej.4)"
        result.selectedLane = b.lane
        result.laneFromFallback = fromFallback
        if let first = b.pts.first {
            let foulY = Float(geo.foulLineY ?? Int(b.lane.yNear))
            result.impactT = detectImpact(url: url, track: b.pts, lane: b.lane, vpY: vpY, afterT: first.t,
                                          foulY: foulY, rot: rot)
        }
        return result
    }

    /// Robust clip background level = median of the working-res background over the lane strip (between the VP
    /// and the foul line, within the lane edges). Used to make the foreground threshold gain-invariant (DEC-117).
    nonisolated private static func laneBgLevel(bg: [UInt8], sw: Int, sh: Int, lane: ODDetectedLane,
                                                stride: Int, vpY: Float, foulY: Float) -> Float {
        let s = Float(stride)
        var vals: [UInt8] = []
        vals.reserveCapacity(sw * sh / 4)
        let y0 = max(0, Int(vpY / s)), y1 = min(sh, Int(foulY / s))
        guard y1 > y0 else { return THR_L_NOMINAL }
        for wy in y0..<y1 {
            let fy = Float(wy) * s
            let (xa, xb) = laneX(lane, fy)
            let wx0 = max(0, Int(xa / s)), wx1 = min(sw, Int(xb / s))
            if wx1 <= wx0 { continue }
            for wx in wx0..<wx1 { vals.append(bg[wy * sw + wx]) }
        }
        if vals.isEmpty { return THR_L_NOMINAL }
        vals.sort()
        return Float(vals[vals.count / 2])
    }

    // MARK: background = per-pixel median of up to maxFrames evenly-sampled luma frames
    private struct Blob { let x: Int; let y: Int; let w: Int; let h: Int; let area: Int }
    private struct Cand { let i: Int; let t: Double; let cx: Float; let ct: Float; let frac: Float }
    // Full-res float blob (working-res Blob scaled up) — the frame the candidate geometry + fragment merge run in.
    private struct FBlob { var x: Float; var y: Float; var w: Float; var h: Float; var a: Float }

    /// Port of cv/track.py `_groups`: merge ball fragments (split by glare / low contrast) whose boxes are within
    /// ~0.35 ball diameters, via union-find, and emit the merged bounding boxes. Exact server constants (0.35·D
    /// gap, 1.6·D width cap, D<8 skip) — no new thresholds. Returns ONLY merged groups (size > 1).
    nonisolated private static func ballFragmentGroups(_ bl: [FBlob], lane: ODDetectedLane) -> [FBlob] {
        let n = bl.count
        if n < 2 { return [] }
        var par = Array(0..<n)
        func find(_ x: Int) -> Int { var i = x; while par[i] != i { par[i] = par[par[i]]; i = par[i] }; return i }
        for i in 0..<n {
            let Di = expDiam(lane, contactRow(lane, top: bl[i].y))
            if Di < 8 || bl[i].w > 1.6 * Di { continue }
            let g = 0.35 * Di
            for j in (i + 1)..<n {
                let a = bl[i], b = bl[j]
                if b.w > 1.6 * Di { continue }
                if a.x - g < b.x + b.w && b.x - g < a.x + a.w && a.y - g < b.y + b.h && b.y - g < a.y + a.h {
                    par[find(i)] = find(j)
                }
            }
        }
        var groups: [Int: [FBlob]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(bl[i]) }
        var out: [FBlob] = []
        for (_, g) in groups where g.count > 1 {
            let x0 = g.map { $0.x }.min()!, y0 = g.map { $0.y }.min()!
            let x1 = g.map { $0.x + $0.w }.max()!, y1 = g.map { $0.y + $0.h }.max()!
            out.append(FBlob(x: x0, y: y0, w: x1 - x0, h: y1 - y0, a: g.reduce(0) { $0 + $1.a }))
        }
        return out
    }

    /// ONE decode pass: collect all timestamps + reservoir-sample up to maxFrames DOWNSCALED luma frames for the
    /// median background. Never holds all frames (that OOM-killed the app). Downscales to ~540p working height
    /// (stride) → ~stride² less memory + faster; blob coords are scaled back to full-res in track().
    nonisolated private static func buildBackground(url: URL, maxFrames: Int, rot: ODRotation = .r0) -> (Int, Int, Int, [Double], [UInt8])? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()
        var ts: [Double] = []; var samples: [[UInt8]] = []
        var sw = 0, sh = 0, stride = 1, i = 0
        var rng: UInt64 = 0x2545F4914F6CDD1D
        func rnd(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(1, n))) }
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }   // shadow cap / superseded (P0 2026-10-29)
            autoreleasepool {                                           // DEC-117: drain per frame (jetsam fix)
                guard let raw = CMSampleBufferGetImageBuffer(sb), let px = OnDeviceDecode.rotated(raw, rot) else { return }
                ts.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)))
                if sw == 0 {
                    let fw = CVPixelBufferGetWidth(px), fh = CVPixelBufferGetHeight(px)
                    stride = max(1, fh / 540); sw = fw / stride; sh = fh / stride
                }
                if samples.count < maxFrames { samples.append(downsampledLuma(px, stride: stride, sw: sw, sh: sh)) }
                else { let j = rnd(i + 1); if j < maxFrames { samples[j] = downsampledLuma(px, stride: stride, sw: sw, sh: sh) } }
                i += 1
            }
        }
        guard !samples.isEmpty, sw > 0, sh > 0 else { return nil }
        var bg = [UInt8](repeating: 0, count: sw * sh)
        let n = samples.count
        var col = [UInt8](repeating: 0, count: n)
        for p in 0..<(sw * sh) {
            for k in 0..<n { col[k] = samples[k][p] }
            col.sort(); bg[p] = col[n / 2]
        }
        return (sw, sh, stride, ts, bg)
    }

    nonisolated private static func forEachLuma(url: URL, stride: Int, sw: Int, sh: Int, rot: ODRotation = .r0, _ body: (Int, [UInt8]) -> Void) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()
        var i = 0
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return }       // shadow cap / superseded (P0 2026-10-29)
            autoreleasepool {                                           // DEC-117: drain per frame (jetsam fix)
                guard let raw = CMSampleBufferGetImageBuffer(sb), let px = OnDeviceDecode.rotated(raw, rot) else { return }
                body(i, downsampledLuma(px, stride: stride, sw: sw, sh: sh))
                i += 1
            }
        }
    }

    /// Downscaled max-channel "luma" (server's max-across-channels diff basis), one UInt8 per working pixel.
    nonisolated private static func downsampledLuma(_ px: CVPixelBuffer, stride: Int, sw: Int, sh: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let rb = CVPixelBufferGetBytesPerRow(px)
        var l = [UInt8](repeating: 0, count: sw * sh)
        guard let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return l }
        for y in 0..<sh {
            let row = (y * stride) * rb
            for x in 0..<sw {
                let p = row + (x * stride) * 4
                l[y * sw + x] = max(base[p], base[p + 1], base[p + 2])
            }
        }
        return l
    }

    // MARK: DEC-131 visual pin-contact (changepoint) — Swift/Accelerate parity port of ops/pin_contact.py
    nonisolated private static func mean(_ a: ArraySlice<Float>) -> Float { a.isEmpty ? 0 : a.reduce(0,+) / Float(a.count) }
    nonisolated private static func median(_ a: [Float]) -> Float { a.isEmpty ? 0 : a.sorted()[a.count/2] }
    nonisolated private static func pctile(_ a: [Float], _ p: Float) -> Float {
        if a.isEmpty { return 0 }; let s = a.sorted(); return s[min(s.count-1, Int(p/100 * Float(s.count)))] }

    /// DEC-131 pin contact = the frame the pins START MOVING, timed by a frame-diff changepoint over the target-lane
    /// pin-deck (bodies above the bases). Parity port of ops/pin_contact.py (deck_motion_series + detect_contact):
    /// foul-anchored window, GRAY luma, reference = first 0.15 s, per-frame body-pixel-change energy, changepoint =
    /// frame maximising mean(E after) − mean(E before), walk back to the rise start, subtract the calibrated offset.
    /// NOISY (handheld residual) / WEAK (far/small deck) decks return nil → the caller withholds rather than guesses.
    nonisolated private static func contactChangepoint(url: URL, track: [TrackPoint], lane: ODDetectedLane,
                                                       vpY: Float, foulY: Float, rot: ODRotation,
                                                       foulTOverride: Double? = nil) -> Double? {
        let pts = track.sorted { $0.t < $1.t }
        guard pts.count >= 6 else { return nil }
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        // foul-cross time from the least-squares u = slope·t + intc fit (same as speed()), or the caller's robust
        // bracket-interpolated foul when provided (the learned track's global fit is small-ball-noise skewed).
        var n = 0.0, st = 0.0, su = 0.0, stt = 0.0, stu = 0.0
        for p in pts { let t = Double(p.t), uu = Double(u(p.contactRow)); n += 1; st += t; su += uu; stt += t*t; stu += t*uu }
        let den = n*stt - st*st; guard abs(den) > 1e-9 else { return nil }
        let slope = (n*stu - st*su)/den, intc = (su - slope*st)/n
        guard slope > 0 else { return nil }
        let tFoul = foulTOverride ?? ((Double(u(foulY)) - intc) / slope)
        // deck ROI: head-pin row ≈ the ball's farthest tracked row; width from the lane geometry there
        let far = pts.max(by: { u($0.contactRow) < u($1.contactRow) })!
        let head = far.contactRow, farD = expDiam(lane, head)
        let (xl, xr) = laneX(lane, head); let padx = 0.2 * (xr - xl)
        let xA = max(0, Int(min(xl, xr) - padx)), xB = Int(max(xl, xr) + padx)
        let y1 = Int(head), y0 = max(0, Int(head - 6 * farD))       // pins stand ABOVE the base row (toward the VP)
        guard y1 > y0 + 6, xB > xA + 6 else { return nil }
        let roiW = xB - xA, bodyH = max(y0 + Int(0.60 * Double(y1 - y0)) - y0, 1)   // bodies = upper 60% of the deck
        let lo = tFoul + 1.2, hi = tFoul + 3.6, refEnd = lo + 0.15  // ~11–25 mph window; first 0.15 s = static ref
        let asset = AVURLAsset(url: url)
        guard let tr = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: tr, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false; reader.add(out); reader.startReading()
        var refs: [[Float]] = []; var ref: [Float]? = nil
        var ts: [Double] = []; var energy: [Float] = []
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            autoreleasepool {
                guard let raw = CMSampleBufferGetImageBuffer(sb), let px = OnDeviceDecode.rotated(raw, rot) else { return }
                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                if t < lo || t > hi { return }
                CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
                let rb = CVPixelBufferGetBytesPerRow(px), W = CVPixelBufferGetWidth(px), H = CVPixelBufferGetHeight(px)
                guard let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return }
                var roi = [Float](repeating: 0, count: roiW * bodyH)
                for yy in 0..<bodyH { let y = y0 + yy; if y < 0 || y >= H { continue }
                    for xx in 0..<roiW { let x = xA + xx; if x < 0 || x >= W { continue }
                        let p = y*rb + x*4                                    // BGRA; GRAY = 0.299R+0.587G+0.114B
                        roi[yy*roiW + xx] = 0.114*Float(base[p]) + 0.587*Float(base[p+1]) + 0.299*Float(base[p+2]) } }
                if t < refEnd { refs.append(roi); return }
                if ref == nil, refs.count >= 2 {
                    var r = [Float](repeating: 0, count: roiW * bodyH); var col = [Float](repeating: 0, count: refs.count)
                    for p in 0..<(roiW * bodyH) { for k in 0..<refs.count { col[k] = refs[k][p] }; col.sort(); r[p] = col[col.count/2] }
                    ref = r
                }
                guard let rr = ref else { return }
                var cnt = 0; for p in 0..<(roiW * bodyH) where abs(roi[p] - rr[p]) > 35 { cnt += 1 }
                ts.append(t); energy.append(Float(cnt) / Float(roiW * bodyH))
            }
        }
        let wa = 15, wb = 8
        guard ts.count > wb + wa + 4 else { return nil }                     // enough frames for the changepoint scan
        let dt = (ts.last! - ts[0]) / Double(ts.count - 1)
        let n0 = max(Int(0.5 / dt), 5)
        let base = median(Array(energy[0..<min(n0, energy.count)])), peak = pctile(energy, 95)
        if base > 0.08 { return nil }                                        // NOISY (stabilisation residual)
        if peak - base < 0.10 { return nil }                                 // WEAK (deck too far/small)
        var bestStep = -Float.infinity, bestC = wb
        for c in wb..<(energy.count - 4) {
            let step = mean(energy[c..<min(c+wa, energy.count)]) - mean(energy[max(c-wb,0)..<c])
            if step > bestStep { bestStep = step; bestC = c }
        }
        let c = bestC
        let before = mean(energy[max(c-wb,0)..<c]), after = mean(energy[c..<min(c+wa, energy.count)])
        let thr = before + 0.20 * (after - before)
        var k = c; while k > max(c-wb, 0) && energy[k-1] > thr { k -= 1 }
        var tRise: Double
        if k > 0 && energy[k] != energy[k-1] {
            let fr = Double(min(max((thr - energy[k-1]) / (energy[k] - energy[k-1]), 0), 1))
            tRise = ts[k-1] + fr * (ts[k] - ts[k-1])
        } else { tRise = ts[k] }
        return tRise - 3.0 * dt                                              // calibrated changepoint offset
    }

    /// Pin-deck arrival = t_impact. Faithful port of cv/track.py detect_impact (tripod: no per-frame warp): the
    /// ROI is a window around the ball's FARTHEST tracked point (≈ the pin deck); for each frame the diff-vs-
    /// reference is measured in a band JUST BEYOND the ball's top (where the pins it is about to hit stand),
    /// tracking the ball frame-by-frame so the measurement MASKS the ball itself and sees only the pins move.
    /// With the ball masked, a 5σ sustained spike is genuine pin motion (a weak strike like IMG_8752 registers
    /// without the ball's own motion false-triggering). The ball cannot strike before it arrives, so a hotness
    /// that fires BEFORE the ball entered the ROI (t_imp < t_enter) is an early reflection → defer to far.t;
    /// otherwise a sustained hotness IS the contact (do NOT drag it to a far point sitting past the pins).
    /// Public wrapper: pin-contact time (changepoint, else 5σ) for a track built OUTSIDE track() — the DEC-131
    /// learned fallback uses it so its track gets the same frame-accurate t_impact as the classical path.
    nonisolated static func impactTime(url: URL, track: [TrackPoint], geo: ODLaneGeometry, rot: ODRotation,
                                       foulTOverride: Double? = nil) -> Double? {
        guard let lane = geo.lanes.first, let vp = geo.vanishingPoint, let first = track.min(by: { $0.t < $1.t }) else { return nil }
        let foulY = Float(geo.foulLineY ?? Int(lane.yNear))
        return detectImpact(url: url, track: track, lane: lane, vpY: vp.y, afterT: first.t, foulY: foulY, rot: rot,
                            foulTOverride: foulTOverride)
    }

    nonisolated private static func detectImpact(url: URL, track: [TrackPoint], lane: ODDetectedLane,
                                                 vpY: Float, afterT: Double, foulY: Float, rot: ODRotation = .r0,
                                                 foulTOverride: Double? = nil) -> Double? {
        let pts = track.sorted { $0.t < $1.t }
        guard pts.count >= 4 else { return nil }
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        let far = pts.max(by: { u($0.contactRow) < u($1.contactRow) })!
        // DEC-132: pin-contact timing is a FAITHFUL PORT of the server PinContactDetector (ops/pin_contact.py). A
        // FIXED target-lane deck ROI (pin-cluster y-span × lane width, upper-60% body mask) is watched over a
        // FOUL-anchored window [t_foul+1.2, t_foul+3.6], NOT the ball's projected arrival. (The old on-device signal
        // tracked a band beside the ball and built its window on the ball's head-pin arrival — on portrait/far clips
        // that band collapsed (series=0, bandFail) and the window ended ~1.7 s before the pins scattered. The
        // geometric crossing anchor is not frame-accurate either (v16 regressed 3 wrong).) The server's foul-anchored
        // deck-motion changepoint with its NOISY/WEAK guards is the authoritative, zero-wrong timer.
        let det = OnDeviceLearnedDetector.shared
        let deck = det?.pinsDeck(url: url, rot: rot, lane: lane)
        lastImpactDebug = "pins=\(det?.hasPinsModel == true) deck=\(deck.map { "h=\(Int($0.head)) y=[\(Int($0.top))..\(Int($0.bot))]" } ?? "nil") far.t=\(String(format: "%.2f", far.t))"
        // No pins deck located → withhold (server parity: PIN_IMPACT_NOT_DETECTED). Only degrade if NO pins model is
        // bundled at all (shouldn't happen — Ball{Lane,Pins}Detector ship in the app).
        guard let deck, det?.hasPinsModel == true else {
            lastImpactDebug += det?.hasPinsModel == true ? " -> WITHHOLD:no_pins_deck" : " -> WITHHOLD:no_pins_model"
            return nil
        }
        // foul-cross time from the ball's u(t) fit (same fit as speed()), or the caller's override.
        var tFoul = foulTOverride ?? Double.nan
        if tFoul.isNaN {
            var n = 0.0, st = 0.0, su = 0.0, stt = 0.0, stu = 0.0
            for p in pts { let t = Double(p.t), uu = Double(u(p.contactRow)); n += 1; st += t; su += uu; stt += t*t; stu += t*uu }
            let den = n*stt - st*st
            guard abs(den) > 1e-9 else { lastImpactDebug += " -> WITHHOLD:degenerate_fit"; return nil }
            let slope = (n*stu - st*su)/den, intc = (su - slope*st)/n
            guard slope > 0 else { lastImpactDebug += " -> WITHHOLD:non_monotonic"; return nil }
            tFoul = (Double(u(foulY)) - intc)/slope
        }
        guard tFoul.isFinite else { lastImpactDebug += " -> WITHHOLD:bad_foul_t"; return nil }
        lastImpactDebug += " tFoul=\(String(format: "%.2f", tFoul))"
        if let tc = pinDeckContactTime(url: url, lane: lane, rot: rot, deck: deck, tFoul: tFoul) {
            lastImpactDebug += " -> OK:deck_contact t=\(String(format: "%.2f", tc))"
            return tc
        }
        return nil
    }

    /// DEC-132 — faithful Swift port of ops/pin_contact.py `deck_motion_series` + `detect_contact`. Returns the
    /// pin-contact time (s) or nil (NOISY/WEAK/short deck → withhold, never a wrong number). FOUL-anchored window; a
    /// fixed deck ROI (pin-cluster span padded × lane width at the head row ±0.2) with the upper-60% body mask; energy
    /// = fraction of body-mask pixels whose grayscale |frame − median-reference| > 35; contact = the largest sustained
    /// STEP walked back to the rise start minus the calibrated 3-frame offset. (Deviation from the server: no
    /// phase-correlation de-jitter — the validation clips are near-static (v11); add it if a handheld clip needs it.)
    nonisolated private static func pinDeckContactTime(url: URL, lane: ODDetectedLane, rot: ODRotation,
                                                       deck: (head: Float, top: Float, bot: Float), tFoul: Double) -> Double? {
        let (xl, xr) = laneX(lane, deck.head); let padX = 0.2 * (xr - xl)
        let spanY = max(deck.bot - deck.top, expDiam(lane, deck.head) * 1.5)   // geometric floor when 1 pin detected
        let y0 = Int(deck.top - 0.25 * spanY), y1 = Int(deck.bot + 0.15 * spanY)
        let x0 = Int(xl - padX), x1 = Int(xr + padX)
        guard y1 - y0 >= 6, x1 - x0 >= 6 else { return nil }
        let roiW = x1 - x0, roiH = y1 - y0
        let bodyBot = max(Int(0.60 * Double(roiH)), 1)        // upper 60% rows = the standing pin bodies
        let bodyCount = bodyBot * roiW
        let loT = tFoul + 1.2, hiT = tFoul + 3.6              // server FOUL_LO/FOUL_HI (≈11–25 mph travel)
        let asset = AVURLAsset(url: url)
        guard let tr = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: tr, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false; reader.add(out); reader.startReading()
        var refFrames: [[Float]] = []; var ref: [Float]? = nil
        var ts: [Double] = []; var energy: [Float] = []
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            autoreleasepool {
                guard let raw = CMSampleBufferGetImageBuffer(sb), let px = OnDeviceDecode.rotated(raw, rot) else { return }
                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                if t < loT { return }
                if t > hiT { reader.cancelReading(); return }
                CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
                let rb = CVPixelBufferGetBytesPerRow(px), W = CVPixelBufferGetWidth(px), H = CVPixelBufferGetHeight(px)
                guard let b = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return }
                var g = [Float](repeating: 0, count: roiW * roiH)
                for yy in 0..<roiH { let y = y0 + yy; if y < 0 || y >= H { continue }
                    for xx in 0..<roiW { let x = x0 + xx; if x < 0 || x >= W { continue }
                        let p = y * rb + x * 4   // BGRA → luma (BT.601, matches cv2 BGR2GRAY)
                        g[yy*roiW+xx] = 0.114*Float(b[p]) + 0.587*Float(b[p+1]) + 0.299*Float(b[p+2]) } }
                if t < loT + 0.15 { refFrames.append(g); return }       // first 0.15 s = static reference
                if ref == nil {
                    guard refFrames.count >= 2 else { reader.cancelReading(); return }
                    var r = [Float](repeating: 0, count: roiW * roiH); var col = [Float](repeating: 0, count: refFrames.count)
                    for p in 0..<(roiW*roiH) { for k in 0..<refFrames.count { col[k] = refFrames[k][p] }; col.sort(); r[p] = col[col.count/2] }
                    ref = r
                }
                guard let rr = ref else { return }
                var changed = 0
                for yy in 0..<bodyBot { let o = yy*roiW; for xx in 0..<roiW where abs(g[o+xx] - rr[o+xx]) > 35 { changed += 1 } }
                ts.append(t); energy.append(Float(changed) / Float(bodyCount))
            }
        }
        lastImpactDebug += " [deckPort win=[\(String(format: "%.2f", loT))..\(String(format: "%.2f", hiT))] refs=\(refFrames.count) E=\(ts.count) roi=\(roiW)x\(roiH) body=\(bodyBot)]"
        return detectContact(t: ts, E: energy)
    }

    /// DEC-132 — port of ops/pin_contact.py `detect_contact`. Largest sustained STEP in the deck-motion energy,
    /// walked back to the rise start, minus the calibrated offset. NOISY (high baseline) / WEAK (no scatter) → nil.
    // spanMin is RAISED from the server's 0.10 to 0.45 on-device: the server runs detect_contact on STABILIZED frames
    // (clean baseline), so a 0.10 scatter is a real signal; on-device RAW frames are noisier, and a weak scatter is
    // indistinguishable from residual motion → the changepoint lands late (IMG_8968 span 0.33 → 11.7 mph for a 17.0
    // ball; IMG_8969 span 0.22/0.32). The correct clips all scatter strongly (span 0.55–0.81), so 0.45 cleanly
    // separates "real pin fall" from "ambiguous deck motion" and WITHHOLDS the rest (accuracy beats coverage; zero
    // plausible-but-wrong). This is the on-device compensation for not warping each frame to a common plate.
    nonisolated private static func detectContact(t: [Double], E: [Float], wa: Int = 15, wb: Int = 8,
                                                  noiseThr: Float = 0.08, spanMin: Float = 0.45,
                                                  refineFrac: Float = 0.20, offsetF: Double = 3.0) -> Double? {
        guard t.count >= 10, E.count == t.count, E.count > wb + 4 else { return nil }
        var diffs: [Double] = []; for i in 1..<t.count { diffs.append(t[i]-t[i-1]) }
        let dt0 = diffs.sorted()[diffs.count/2]; let dt = dt0 > 0 ? dt0 : 1.0/60
        let n0 = min(max(Int(0.5/dt), 5), E.count)
        let base = Array(E[0..<n0]).sorted()[n0/2]                       // median of the first n0
        let sorted = E.sorted(); let peak = sorted[min(Int(0.95 * Float(E.count - 1)), E.count - 1)]
        lastImpactDebug += " {base=\(String(format: "%.3f", base)) peak=\(String(format: "%.3f", peak)) span=\(String(format: "%.3f", peak-base)) dt=\(String(format: "%.3f", dt))}"
        if base > noiseThr { return nil }                               // NOISY (handheld stabilisation residual)
        if peak - base < spanMin { return nil }                         // WEAK (deck too far/small)
        func mean(_ s: ArraySlice<Float>) -> Float { s.isEmpty ? 0 : s.reduce(0,+)/Float(s.count) }
        var bestStep = -Float.infinity, bestC = wb
        for c in wb..<(E.count - 4) {
            let step = mean(E[c..<min(c+wa, E.count)]) - mean(E[max(c-wb,0)..<c])
            if step > bestStep { bestStep = step; bestC = c }
        }
        let c = bestC
        let before = mean(E[max(c-wb,0)..<c]); let after = mean(E[c..<min(c+wa, E.count)])
        let thr = before + refineFrac * (after - before)
        var k = c
        while k > max(c-wb, 0) && E[k-1] > thr { k -= 1 }
        let tRise: Double
        if k > 0 && E[k] != E[k-1] {
            let fr = Double(min(max((thr - E[k-1]) / (E[k] - E[k-1]), 0), 1))
            tRise = t[k-1] + fr * (t[k] - t[k-1])
        } else { tRise = t[k] }
        return tRise - offsetF * dt
    }

    // MARK: foreground blobs — diff vs bg, threshold, 3x3 open, connected components (union-find)
    nonisolated private static func foregroundBlobs(luma: [UInt8], bg: [UInt8], w: Int, h: Int, thr: Int) -> [Blob] {
        var m = [UInt8](repeating: 0, count: w * h)
        for p in 0..<(w * h) where abs(Int(luma[p]) - Int(bg[p])) > thr { m[p] = 1 }
        erode3(&m, w: w, h: h); dilate3(&m, w: w, h: h)     // 3x3 open
        // union-find connected components (4-conn), accumulate bbox + area
        var parent = [Int](repeating: -1, count: w * h)
        func find(_ a: Int) -> Int { var a = a; while parent[a] != a { parent[a] = parent[parent[a]]; a = parent[a] }; return a }
        for p in 0..<(w * h) where m[p] == 1 {
            parent[p] = p
            let x = p % w, y = p / w
            if x > 0 && m[p - 1] == 1 { let r = find(p - 1); parent[r] = p }
            if y > 0 && m[p - w] == 1 { let r = find(p - w); parent[find(p)] = r }
        }
        var minx = [Int: Int](), miny = [Int: Int](), maxx = [Int: Int](), maxy = [Int: Int](), area = [Int: Int]()
        for p in 0..<(w * h) where m[p] == 1 {
            let r = find(p); let x = p % w, y = p / w
            area[r, default: 0] += 1
            minx[r] = min(minx[r] ?? x, x); maxx[r] = max(maxx[r] ?? x, x)
            miny[r] = min(miny[r] ?? y, y); maxy[r] = max(maxy[r] ?? y, y)
        }
        var out: [Blob] = []
        for (r, a) in area where a >= 12 {
            out.append(Blob(x: minx[r]!, y: miny[r]!, w: maxx[r]! - minx[r]! + 1, h: maxy[r]! - miny[r]! + 1, area: a))
        }
        return out
    }

    nonisolated private static func erode3(_ m: inout [UInt8], w: Int, h: Int) {
        let s = m
        for y in 1..<(h - 1) { for x in 1..<(w - 1) { let p = y * w + x
            if s[p] == 1 && !(s[p-1]==1 && s[p+1]==1 && s[p-w]==1 && s[p+w]==1) { m[p] = 0 } } }
    }
    nonisolated private static func dilate3(_ m: inout [UInt8], w: Int, h: Int) {
        let s = m
        for y in 1..<(h - 1) { for x in 1..<(w - 1) { let p = y * w + x
            if s[p] == 0 && (s[p-1]==1 || s[p+1]==1 || s[p-w]==1 || s[p+w]==1) { m[p] = 1 } } }
    }

    // MARK: RANSAC link (port of track.py link) — u = 1/(ct - vpY) is ~linear in lane distance; u(t) ~linear
    // in time for a rolling ball. The DISCRIMINATING constraints (vs the loose first pass): the ball travels
    // foul→pins, so u INCREASES (slope > 0); the roll is SHORT (≤ ~5 s); it covers real lane distance (u-range).
    // This rejects the ball return (u decreasing), the bowler (tiny motion), and whole-clip flat fits.
    nonisolated private static func ransacLink(_ perFrame: [[Cand]], vpY: Float, iters: Int = 6000) -> [TrackPoint] {
        // DETERMINISM (DEC-126 P0): pin the candidate order. Swift Dictionary/Set iteration uses a per-RUN random
        // hash seed, so any upstream unordered structure (or an unstable sort downstream) made the RANSAC sample
        // different (a,b) each run → a 1-frame-different track → the 8754 16.4↔17.4 non-determinism. Sorting flat by
        // (t, i, cx) makes the whole linker reproducible regardless of upstream order.
        let flat = perFrame.flatMap { $0 }.sorted {
            ($0.t, Double($0.i), Double($0.cx)) < ($1.t, Double($1.i), Double($1.cx)) }
        guard flat.count >= 8 else { return [] }
        func u(_ c: Cand) -> Float { 1 / max(c.ct - vpY, 1) }
        let uRange = (flat.map { u($0) }.max() ?? 1) - (flat.map { u($0) }.min() ?? 0)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(1, n))) }
        var best: [Cand] = []
        for _ in 0..<iters {
            let a = flat[rnd(flat.count)], b = flat[rnd(flat.count)]
            if a.i == b.i { continue }
            let dt = Float(b.t - a.t); if abs(dt) < 0.03 { continue }
            let slope = (u(b) - u(a)) / dt
            if slope <= 0 { continue }                      // require ball moving foul→pins (u increasing)
            let intc = u(a) - slope * Float(a.t)
            var chosen: [Int: Cand] = [:]
            for c in flat {
                let pred = slope * Float(c.t) + intc
                let tol = 0.012 * abs(u(c)) + 1e-4          // tighter than the first pass
                if abs(u(c) - pred) < tol {
                    if let ex = chosen[c.i] { if abs(u(c) - pred) < abs(u(ex) - pred) { chosen[c.i] = c } }
                    else { chosen[c.i] = c }
                }
            }
            let inl = chosen.values.sorted { ($0.t, Double($0.i)) < ($1.t, Double($1.i)) }
            guard inl.count >= 8, let f = inl.first, let l = inl.last else { continue }
            let span = l.t - f.t
            let du = u(l) - u(f)
            // a real roll: short in time, net motion toward the pins covering a real fraction of the lane
            guard span >= 0.5, span <= 5.0, du > 0.35 * uRange else { continue }
            if inl.count > best.count { best = inl }
        }
        return best.sorted { ($0.t, Double($0.i)) < ($1.t, Double($1.i)) }
            .map { TrackPoint(i: $0.i, t: $0.t, cx: $0.cx, contactRow: $0.ct, frac: $0.frac) }
    }
}
