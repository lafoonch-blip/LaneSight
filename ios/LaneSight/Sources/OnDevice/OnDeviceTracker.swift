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
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        // least-squares u = slope*t + intc over the track
        var n = 0.0, st = 0.0, su = 0.0, stt = 0.0, stu = 0.0
        for p in pts { let t = Double(p.t), uu = Double(u(p.contactRow)); n += 1; st += t; su += uu; stt += t * t; stu += t * uu }
        let den = n * stt - st * st
        guard abs(den) > 1e-9 else { return fail("degenerate trajectory fit") }
        let slope = (n * stu - st * su) / den
        let intc = (su - slope * st) / n
        guard slope > 0 else { return fail("non-monotonic track (ball not clearly moving toward the pins)") }
        let tFoulCross = (Double(u(Float(foulY))) - intc) / slope     // ball crosses the foul line
        // t_impact = ball-at-pins ("ball centre at first head-pin contact"). Use the pin-deck MOTION detector
        // (track.impactT), which marks the pin location directly, MINUS the pin-fall latency: a struck pin takes
        // ~0.15 s to move visibly, so the motion spike lags ball-contact by that much (measured +0.17/+0.18 s on
        // 8751/8754). The lane far extent is NOT the pin row (the ball tracks past it; the true pin depth needs the
        // gated metric plane), so a trajectory extrapolation undershoots — only used as a fallback when no spike.
        let tImpact: Double
        if let it = track.impactT { tImpact = it }   // ball-masked pin-motion ≈ true contact (no pin-fall offset)
        else {
            // No pin-motion spike (e.g. a weak strike on IMG_8752). Fall back to the ball's FARTHEST-down-lane
            // tracked point (max u = nearest the pins), mirroring the server's `far = track[argmax(u)]`. This is
            // the turning point: once the ball contacts the pins it deflects/slows and its down-lane u stops
            // increasing, so argmax(u) ≈ ball-at-pins — better than the last-by-time point, which can be the ball
            // continuing into the pit.
            let far = pts.max(by: { u($0.contactRow) < u($1.contactRow) })!
            tImpact = far.t
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

    nonisolated static func track(url: URL, geo: ODLaneGeometry, diffThr: Int = 35,
                                  maxBgFrames: Int = 12, rot: ODRotation = .r0) -> BallTrack {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let lane = geo.lanes.first, let vp = geo.vanishingPoint,
              let (sw, sh, stride, ts, bg) = buildBackground(url: url, maxFrames: maxBgFrames, rot: rot) else {
            return BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        // Pass 2: per-frame foreground → blobs (at working res) → scale up → diameter-gated candidates (full-res geo).
        // Physical gates (match the roll, reject the bowler/approach + the ball return):
        //   • ON the lane laterally: 0 ≤ frac ≤ 1 (+ small margin)
        //   • up-lane from the foul: contactRow between the VP and the foul line (not behind the foul in the approach)
        let foulY = Float(geo.foulLineY ?? Int(lane.yNear))
        let vpY = vp.y
        // brightness-relative threshold: scale diffThr by this clip's own background level over the lane strip
        // (working coords) so a gain-scaled copy of the clip segments identically (DEC-117).
        let bgLevel = laneBgLevel(bg: bg, sw: sw, sh: sh, lane: lane, stride: stride, vpY: vpY, foulY: foulY)
        let thrEff = Int(min(THR_MAX, max(THR_MIN, Float(diffThr) * bgLevel / THR_L_NOMINAL)).rounded())
        var perFrame: [[Cand]] = []
        var scanned = 0
        let s = Float(stride)
        forEachLuma(url: url, stride: stride, sw: sw, sh: sh, rot: rot) { i, luma in
            scanned += 1
            let blobs = foregroundBlobs(luma: luma, bg: bg, w: sw, h: sh, thr: thrEff)
            var cs: [Cand] = []
            for b in blobs {
                let bx = Float(b.x) * s, by = Float(b.y) * s, bw = Float(b.w) * s, bh = Float(b.h) * s, ba = Float(b.area) * s * s
                let ct = contactRow(lane, top: by)
                let D = expDiam(lane, ct)
                if D < 8 { continue }
                if ct > foulY + 40 || ct < vpY + 10 { continue }   // on the lane surface (up-lane from the foul)
                let ratio = bw / D
                if ratio > 0.7 && ratio < 1.35 && bh < 3.2 * D && ba > 0.25 * D * D {
                    let (xa, xb) = laneX(lane, ct)
                    let cx = bx + bw / 2
                    let frac = (cx - xa) / (xb - xa)
                    if frac < -0.05 || frac > 1.05 { continue }    // on the lane laterally (rejects the ball return)
                    cs.append(Cand(i: i, t: i < ts.count ? ts[i] : (ts.last ?? 0), cx: cx, ct: ct, frac: frac))
                }
            }
            perFrame.append(cs)
        }
        let candFrames = perFrame.filter { !$0.isEmpty }.count
        let pts = ransacLink(perFrame, vpY: vp.y)
        var result = BallTrack(points: pts, framesScanned: scanned, candidateFrames: candFrames,
                               seconds: CFAbsoluteTimeGetCurrent() - t0)
        if let first = pts.first {
            result.impactT = detectImpact(url: url, track: pts, lane: lane, vpY: vpY, afterT: first.t, rot: rot)
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

    /// Pin-deck arrival = t_impact. Faithful port of cv/track.py detect_impact (tripod: no per-frame warp): the
    /// ROI is a window around the ball's FARTHEST tracked point (≈ the pin deck); for each frame the diff-vs-
    /// reference is measured in a band JUST BEYOND the ball's top (where the pins it is about to hit stand),
    /// tracking the ball frame-by-frame so the measurement MASKS the ball itself and sees only the pins move.
    /// With the ball masked, a 5σ sustained spike is genuine pin motion (a weak strike like IMG_8752 registers
    /// without the ball's own motion false-triggering). The ball cannot strike before it arrives, so a hotness
    /// that fires BEFORE the ball entered the ROI (t_imp < t_enter) is an early reflection → defer to far.t;
    /// otherwise a sustained hotness IS the contact (do NOT drag it to a far point sitting past the pins).
    nonisolated private static func detectImpact(url: URL, track: [TrackPoint], lane: ODDetectedLane,
                                                 vpY: Float, afterT: Double, rot: ODRotation = .r0) -> Double? {
        let pts = track.sorted { $0.t < $1.t }
        guard pts.count >= 4 else { return nil }
        func u(_ ct: Float) -> Float { 1 / max(ct - vpY, 1) }
        let far = pts.max(by: { u($0.contactRow) < u($1.contactRow) })!
        let farD = expDiam(lane, far.contactRow)
        let yA = max(0, Int(far.contactRow - 4 * farD)), yB = Int(far.contactRow + 4 * farD)
        let (xaF, xbF) = laneX(lane, far.contactRow); let padX = 0.4 * (xbF - xaF)
        let xA = max(0, Int(xaF - padX)), xB = Int(xbF + padX)
        guard yB > yA + 8, xB > xA + 8 else { return nil }
        let roiW = xB - xA, roiH = yB - yA
        // t_enter: first track time the ball's top enters the ROI (ct − D < yB)
        var tEnter = far.t - 0.5
        for p in pts where Double(p.contactRow) - Double(expDiam(lane, p.contactRow)) < Double(yB) { tEnter = p.t; break }
        // ball interpolation arrays
        let tt = pts.map { Double($0.t) }, cxA = pts.map { $0.cx }, ctA = pts.map { $0.contactRow }
        func ballAt(_ t: Double) -> (Float, Float) {
            var k = 1; while k < tt.count && tt[k] < t { k += 1 }; k = min(max(k, 1), tt.count - 1)
            let a = Float(min(max((t - tt[k-1]) / max(tt[k]-tt[k-1], 1e-6), 0), 1))
            return (cxA[k-1] + a * (cxA[k]-cxA[k-1]), ctA[k-1] + a * (ctA[k]-ctA[k-1]))
        }
        let asset = AVURLAsset(url: url)
        guard let tr = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: tr, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false; reader.add(out); reader.startReading()
        var refs: [[Float]] = []; var ref: [Float]? = nil; var series: [(t: Double, v: Float)] = []
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            autoreleasepool {
                guard let raw = CMSampleBufferGetImageBuffer(sb), let px = OnDeviceDecode.rotated(raw, rot) else { return }
                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
                if t < tEnter - 0.5 || t > far.t + 0.6 { return }
                CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
                let rb = CVPixelBufferGetBytesPerRow(px), W = CVPixelBufferGetWidth(px), H = CVPixelBufferGetHeight(px)
                guard let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return }
                var roi = [Float](repeating: 0, count: roiW * roiH)
                for yy in 0..<roiH { let y = yA + yy; if y < 0 || y >= H { continue }
                    for xx in 0..<roiW { let x = xA + xx; if x < 0 || x >= W { continue }
                        let p = y * rb + x * 4; roi[yy * roiW + xx] = Float(max(base[p], base[p+1], base[p+2])) } }
                if t < tEnter - 0.05 { refs.append(roi); return }
                if ref == nil, !refs.isEmpty {
                    var r = [Float](repeating: 0, count: roiW * roiH); var col = [Float](repeating: 0, count: refs.count)
                    for p in 0..<(roiW * roiH) { for k in 0..<refs.count { col[k] = refs[k][p] }; col.sort(); r[p] = col[col.count/2] }
                    ref = r
                }
                guard let rr = ref else { return }
                // band JUST BEYOND the ball's top (toward the pins), tracking the ball → masks the ball itself
                let (bx, by) = ballAt(t); let bd = expDiam(lane, by)
                let r0 = max(0, Int(by - 2.2*bd) - yA), r1 = min(roiH, Int(by - 1.15*bd) - yA)
                let c0 = max(0, Int(bx - 1.3*bd) - xA), c1 = min(roiW, Int(bx + 1.3*bd) - xA)
                guard r1 > r0, c1 > c0 else { return }
                var diffs: [Float] = []; diffs.reserveCapacity((r1-r0)*(c1-c0))
                for yy in r0..<r1 { for xx in c0..<c1 { let p = yy*roiW + xx; diffs.append(abs(roi[p] - rr[p])) } }
                diffs.sort(); let pct95 = diffs[min(diffs.count-1, Int(0.95 * Float(diffs.count)))]
                series.append((t, pct95))
            }
        }
        guard series.count > 6 else { return nil }
        // baseline + MAD over pre-arrival frames (server: E[:,0] < t_enter+0.6)
        let pre = series.filter { $0.t < tEnter + 0.6 }.map { $0.v }
        guard !pre.isEmpty else { return nil }
        let med = pre.sorted()[pre.count/2]
        let mad = pre.map { abs($0 - med) }.sorted()[pre.count/2]
        let base = med, sd = 1.4826 * mad + 2
        let thr = base + 5 * sd
        var hotness: Double? = nil
        for k in 0..<(series.count - 3) {
            if series[k].v > thr && series[k..<min(k+4, series.count)].filter({ $0.v > thr }).count >= 3 { hotness = series[k].t; break }
        }
        guard let h = hotness else { return nil }
        // clamp (DEC-117): a hotness BEFORE the ball entered the ROI is an early reflection → defer to far.t.
        if Double(far.t) > h && h < tEnter { return Double(far.t) }
        // Otherwise both estimates tend to OVERSHOOT the true contact — the pin-motion hotness by the pin-fall
        // latency, the farthest tracked point by the ball continuing into the pit on a strike — so take the
        // EARLIER of the two as the best contact estimate (recovers 8754's late hotness without re-overshooting).
        return min(h, Double(far.t))
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
