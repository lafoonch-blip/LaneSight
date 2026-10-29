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
struct BallTrack: Equatable {
    let points: [TrackPoint]
    let framesScanned: Int
    let candidateFrames: Int
    let seconds: Double
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

    nonisolated static func track(url: URL, geo: ODLaneGeometry, diffThr: Int = 35,
                                  maxBgFrames: Int = 12) -> BallTrack {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let lane = geo.lanes.first, let vp = geo.vanishingPoint,
              let (w, h, ts, bg) = buildBackground(url: url, maxFrames: maxBgFrames) else {
            return BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: CFAbsoluteTimeGetCurrent() - t0)
        }
        // Pass 2: per-frame foreground → blobs → diameter-gated candidates.
        var perFrame: [[Cand]] = []
        var scanned = 0
        forEachLuma(url: url, w: w, h: h) { i, luma in
            scanned += 1
            let blobs = foregroundBlobs(luma: luma, bg: bg, w: w, h: h, thr: diffThr)
            var cs: [Cand] = []
            for b in blobs {
                let ct = contactRow(lane, top: Float(b.y))
                let D = expDiam(lane, ct)
                if D < 8 { continue }
                let ratio = Float(b.w) / D
                if ratio > 0.7 && ratio < 1.35 && Float(b.h) < 3.2 * D && Float(b.area) > 0.25 * D * D {
                    let (xa, xb) = laneX(lane, ct)
                    let cx = Float(b.x) + Float(b.w) / 2
                    cs.append(Cand(i: i, t: ts[min(i, ts.count - 1)], cx: cx, ct: ct, frac: (cx - xa) / (xb - xa)))
                }
            }
            perFrame.append(cs)
        }
        let candFrames = perFrame.filter { !$0.isEmpty }.count
        let pts = ransacLink(perFrame, vpY: vp.y)
        return BallTrack(points: pts, framesScanned: scanned, candidateFrames: candFrames,
                         seconds: CFAbsoluteTimeGetCurrent() - t0)
    }

    // MARK: background = per-pixel median of up to maxFrames evenly-sampled luma frames
    private struct Blob { let x: Int; let y: Int; let w: Int; let h: Int; let area: Int }
    private struct Cand { let i: Int; let t: Double; let cx: Float; let ct: Float; let frac: Float }

    nonisolated private static func buildBackground(url: URL, maxFrames: Int) -> (Int, Int, [Double], [UInt8])? {
        // First decode: collect luma for all frames' timestamps + sample up to maxFrames evenly for the median.
        guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: AVURLAsset(url: url)) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()
        var ts: [Double] = []; var samples: [[UInt8]] = []; var w = 0, h = 0
        var all: [[UInt8]] = []
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            ts.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)))
            let l = luma(px, w: &w, h: &h)
            all.append(l)
        }
        guard !all.isEmpty, w > 0, h > 0 else { return nil }
        let step = max(1, all.count / maxFrames)
        var idx = 0
        while idx < all.count && samples.count < maxFrames { samples.append(all[idx]); idx += step }
        // per-pixel median across the sampled frames
        var bg = [UInt8](repeating: 0, count: w * h)
        let n = samples.count
        var col = [UInt8](repeating: 0, count: n)
        for p in 0..<(w * h) {
            for k in 0..<n { col[k] = samples[k][p] }
            col.sort()
            bg[p] = col[n / 2]
        }
        return (w, h, ts, bg)
    }

    nonisolated private static func forEachLuma(url: URL, w: Int, h: Int, _ body: (Int, [UInt8]) -> Void) {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: AVURLAsset(url: url)) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()
        var i = 0; var ww = 0, hh = 0
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let l = luma(px, w: &ww, h: &hh)
            if ww == w && hh == h { body(i, l) }
            i += 1
        }
    }

    /// Max-channel "luma" (matches the server's max-across-channels diff basis), one UInt8 per pixel.
    nonisolated private static func luma(_ px: CVPixelBuffer, w: inout Int, h: inout Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        w = CVPixelBufferGetWidth(px); h = CVPixelBufferGetHeight(px)
        let rb = CVPixelBufferGetBytesPerRow(px)
        var l = [UInt8](repeating: 0, count: w * h)
        guard let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return l }
        for y in 0..<h {
            let row = y * rb
            for x in 0..<w {
                let p = row + x * 4
                l[y * w + x] = max(base[p], base[p + 1], base[p + 2])
            }
        }
        return l
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

    // MARK: RANSAC link (port of track.py link) — u = 1/(ct - vpY) is ~linear in lane distance; u(t) ~quadratic.
    nonisolated private static func ransacLink(_ perFrame: [[Cand]], vpY: Float, iters: Int = 2000) -> [TrackPoint] {
        let flat = perFrame.flatMap { $0 }
        guard flat.count >= 10 else { return [] }
        func u(_ c: Cand) -> Float { 1 / (c.ct - vpY) }
        var bestInliers: [Cand] = []
        var rng: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(1, n))) }
        for _ in 0..<iters {
            let a = flat[rnd(flat.count)], b = flat[rnd(flat.count)]
            if a.i == b.i { continue }
            let dt = Float(b.t - a.t); if abs(dt) < 1e-4 { continue }
            let slope = (u(b) - u(a)) / dt                 // linear u(t) seed
            let intc = u(a) - slope * Float(a.t)
            // one candidate per frame closest to the line, within tolerance
            var chosen: [Int: Cand] = [:]
            for c in flat {
                let pred = slope * Float(c.t) + intc
                let tol = 0.02 * abs(u(c)) + 1e-4
                if abs(u(c) - pred) < tol {
                    if let ex = chosen[c.i] {
                        if abs(u(c) - pred) < abs(u(ex) - pred) { chosen[c.i] = c }
                    } else { chosen[c.i] = c }
                }
            }
            let inl = Array(chosen.values)
            if inl.count > bestInliers.count { bestInliers = inl }
        }
        let sorted = bestInliers.sorted { $0.t < $1.t }
        return sorted.map { TrackPoint(i: $0.i, t: $0.t, cx: $0.cx, contactRow: $0.ct, frac: $0.frac) }
    }
}
