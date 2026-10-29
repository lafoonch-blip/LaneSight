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
}
struct BallTrack: Equatable {
    let points: [TrackPoint]
    let framesScanned: Int
    let candidateFrames: Int
    let seconds: Double
    var impactT: Double? = nil          // detected pin-deck arrival time (preferred t_impact)
    var spanFrac: Float { (points.first.map { p in (points.last!.frac - p.frac) }) ?? 0 }
}

// Physical constants (match cv/track.py / lane_geometry).
private nonisolated(unsafe) let BALL_IN: Float = 8.5
private nonisolated(unsafe) let LANE_IN: Float = 41.5

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
        // t_impact: detected pin-deck arrival if available (exact), else extrapolate to the lane far extent.
        let tImpact = track.impactT ?? ((Double(u(Float(lane.yFar))) - intc) / slope)
        let release = tFoulCross - 0.068                              // RELEASE_OFFSET_S (cv/metrics.py)
        let dt = tImpact - release
        guard dt > 0.5 && dt < 5 else { return fail("implausible foul→impact interval (\(String(format: "%.2f", dt))s)") }
        let mph = Float(60.0 / dt * 3600.0 / 5280.0)
        guard mph > 5 && mph < 30 else { return fail("speed out of range (\(String(format: "%.1f", mph)) mph) — track likely short of the pins") }
        return SpeedEstimate(mph: mph, tRelease: release, tImpact: tImpact, entryFrac: pts.last!.frac, basis: "best_effort",
                             note: "fitted-trajectory anchors (foul + lane far extent ≈ pins); exact once pin-impact detection lands")
    }

    nonisolated static func track(url: URL, geo: ODLaneGeometry, diffThr: Int = 35,
                                  maxBgFrames: Int = 12) -> BallTrack {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let lane = geo.lanes.first, let vp = geo.vanishingPoint,
              let (sw, sh, stride, ts, bg) = buildBackground(url: url, maxFrames: maxBgFrames) else {
            return BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        // Pass 2: per-frame foreground → blobs (at working res) → scale up → diameter-gated candidates (full-res geo).
        // Physical gates (match the roll, reject the bowler/approach + the ball return):
        //   • ON the lane laterally: 0 ≤ frac ≤ 1 (+ small margin)
        //   • up-lane from the foul: contactRow between the VP and the foul line (not behind the foul in the approach)
        let foulY = Float(geo.foulLineY ?? Int(lane.yNear))
        let vpY = vp.y
        var perFrame: [[Cand]] = []
        var scanned = 0
        let s = Float(stride)
        forEachLuma(url: url, stride: stride, sw: sw, sh: sh) { i, luma in
            scanned += 1
            let blobs = foregroundBlobs(luma: luma, bg: bg, w: sw, h: sh, thr: diffThr)
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
            result.impactT = detectImpact(url: url, lane: lane, vpY: vpY, foulY: foulY, afterT: first.t)
        }
        return result
    }

    // MARK: background = per-pixel median of up to maxFrames evenly-sampled luma frames
    private struct Blob { let x: Int; let y: Int; let w: Int; let h: Int; let area: Int }
    private struct Cand { let i: Int; let t: Double; let cx: Float; let ct: Float; let frac: Float }

    /// ONE decode pass: collect all timestamps + reservoir-sample up to maxFrames DOWNSCALED luma frames for the
    /// median background. Never holds all frames (that OOM-killed the app). Downscales to ~540p working height
    /// (stride) → ~stride² less memory + faster; blob coords are scaled back to full-res in track().
    nonisolated private static func buildBackground(url: URL, maxFrames: Int) -> (Int, Int, Int, [Double], [UInt8])? {
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
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            ts.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)))
            if sw == 0 {
                let fw = CVPixelBufferGetWidth(px), fh = CVPixelBufferGetHeight(px)
                stride = max(1, fh / 540); sw = fw / stride; sh = fh / stride
            }
            if samples.count < maxFrames { samples.append(downsampledLuma(px, stride: stride, sw: sw, sh: sh)) }
            else { let j = rnd(i + 1); if j < maxFrames { samples[j] = downsampledLuma(px, stride: stride, sw: sw, sh: sh) } }
            i += 1
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

    nonisolated private static func forEachLuma(url: URL, stride: Int, sw: Int, sh: Int, _ body: (Int, [UInt8]) -> Void) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()
        var i = 0
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            body(i, downsampledLuma(px, stride: stride, sw: sw, sh: sh))
            i += 1
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

    /// Pin-deck arrival = t_impact. Watches the far quarter of the lane (where the pins stand); the first
    /// sustained motion spike there after the ball is rolling is the ball reaching the pins (cf. cv/track.py
    /// detect_impact, simplified for a tripod clip: reference = median of the first frames, no warp).
    nonisolated private static func detectImpact(url: URL, lane: ODDetectedLane, vpY: Float, foulY: Float, afterT: Double) -> Double? {
        let rTop = max(0, Int(vpY) + 5), rBot = Int(vpY + 0.30 * (foulY - vpY))
        guard rBot > rTop + 8 else { return nil }
        let (xaF, xbF) = laneX(lane, Float(rBot)); let padX = 0.5 * (xbF - xaF)
        let cL = max(0, Int(xaF - padX)), cR = Int(xbF + padX)
        guard cR > cL + 8 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let tr = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: tr, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false; reader.add(out); reader.startReading()
        let bw = cR - cL, bh = rBot - rTop
        var refs: [[Float]] = []; var ref: [Float]? = nil; var series: [(Double, Float)] = []
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            CVPixelBufferLockBaseAddress(px, .readOnly)
            let rb = CVPixelBufferGetBytesPerRow(px), W = CVPixelBufferGetWidth(px), H = CVPixelBufferGetHeight(px)
            var band = [Float](repeating: 0, count: bw * bh)
            if let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) {
                for yy in 0..<bh { let y = rTop + yy; if y < 0 || y >= H { continue }
                    for xx in 0..<bw { let x = cL + xx; if x < 0 || x >= W { continue }
                        let p = y * rb + x * 4; band[yy * bw + xx] = Float(max(base[p], base[p + 1], base[p + 2])) } }
            }
            CVPixelBufferUnlockBaseAddress(px, .readOnly)
            if refs.count < 10 { refs.append(band) }
            else {
                if ref == nil {
                    var r = [Float](repeating: 0, count: bw * bh); var col = [Float](repeating: 0, count: refs.count)
                    for p in 0..<(bw * bh) { for k in 0..<refs.count { col[k] = refs[k][p] }; col.sort(); r[p] = col[col.count / 2] }
                    ref = r
                }
                var acc: Float = 0; let rr = ref!
                for p in 0..<(bw * bh) { acc += abs(band[p] - rr[p]) }
                series.append((t, acc / Float(bw * bh)))
            }
        }
        guard series.count > 10 else { return nil }
        let quiet = series.filter { $0.0 < afterT }.map { $0.1 }
        let base = quiet.isEmpty ? (series.map { $0.1 }.min() ?? 0) : quiet.reduce(0, +) / Float(quiet.count)
        let sd = quiet.count > 2 ? (quiet.map { ($0 - base) * ($0 - base) }.reduce(0, +) / Float(quiet.count)).squareRoot() : base * 0.5 + 1
        let thr = base + max(5 * sd, 8)
        let peakT = series.max(by: { $0.1 < $1.1 })?.0 ?? 0
        #if DEBUG
        print("ONDEV: impact band rows[\(rTop)-\(rBot)] cols[\(cL)-\(cR)] frames=\(series.count) base=\(String(format: "%.1f", base)) sd=\(String(format: "%.1f", sd)) thr=\(String(format: "%.1f", thr)) peak=\(String(format: "%.1f", series.map { $0.1 }.max() ?? 0))@\(String(format: "%.2f", peakT))s afterT=\(String(format: "%.2f", afterT))")
        #endif
        for k in 0..<(series.count - 3) {
            if series[k].0 < afterT { continue }
            if series[k].1 > thr && series[k..<min(k + 4, series.count)].filter({ $0.1 > thr }).count >= 2 { return series[k].0 }
        }
        return nil
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
        let flat = perFrame.flatMap { $0 }
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
            let inl = chosen.values.sorted { $0.t < $1.t }
            guard inl.count >= 8, let f = inl.first, let l = inl.last else { continue }
            let span = l.t - f.t
            let du = u(l) - u(f)
            // a real roll: short in time, net motion toward the pins covering a real fraction of the lane
            guard span >= 0.5, span <= 5.0, du > 0.35 * uRange else { continue }
            if inl.count > best.count { best = inl }
        }
        return best.sorted { $0.t < $1.t }
            .map { TrackPoint(i: $0.i, t: $0.t, cx: $0.cx, contactRow: $0.ct, frac: $0.frac) }
    }
}
