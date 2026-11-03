import Foundation
import AVFoundation
import Accelerate
import CoreVideo
import simd

// DEC-102/103/117 — On-device lane geometry, ported LINE-FOR-LINE from lanesight_core/cv/lanes.py find_lanes:
// saturated-wood HSV mask → morphology → per-row wood runs linked into edge tracks → robust edge lines
// (x = a·y + b) → common vanishing point → per-lane FOUL-LINE fit (_foul) → EDGE REFINEMENT off the loose mask
// (_refine_edges) → final VP re-solve. Runs on the stabilized background PLATE (the same input the Python
// reference `find_lanes(bg)` consumes), not a raw frame — that is what the committed ios_parity_golden encodes.
//
// Fitting + geometry are done in Double (the Python reference is float64; a Float normal-equations fit at
// y≈1920 cannot hold the 2 px foul / 5 px VP parity tolerance). Public structs stay Float for the tracker/
// metric-plane consumers; the refined scalars are well within Float precision.
//
// NOT ported (none of the IMG_8751-54 validation clips exercise them; find_lanes falls back only when the
// saturation pass finds nothing): the pale-lane gutter fallback (_gutter_fallback / _ransac_edge) and the
// classify_capture_view gate. Flagged so the gap is explicit — see OnDeviceLaneParityTests.

nonisolated struct LaneEdge: Equatable { let a: Float; let b: Float; let resid: Float }   // x = a*y + b
nonisolated struct ODDetectedLane: Equatable {
    let left: LaneEdge; let right: LaneEdge
    let yNear: Int; let yFar: Int
    let widthNearPx: Float
}
/// Per-stage intermediates for parity diagnosis against scratchpad parity_intermediates.json.
nonisolated struct ODLaneDebug: Equatable {
    var maskPixels: Int = 0       // strict (winning-floor) mask pixel count
    var loosePixels: Int = 0      // loose mask pixel count (s_min = min(60, used_s))
    var nTracks: Int = 0          // tracks surviving the min_rows gate
    var nLanes: Int = 0           // lanes with fittable L/R edges
    var nGood: Int = 0            // lanes agreeing with the raw VP
    var rawVPx: Double = .nan     // raw (pre-refine) VP
    var rawVPy: Double = .nan
    var usedS: Int = 0
    var rawLaneInfo: [[Double]] = []   // DEC-128: per raw lane [center_x@yNear, widthNear, dl, dr] vs the raw VP
}
nonisolated struct ODLaneGeometry: Equatable {
    let lanes: [ODDetectedLane]          // lanes agreeing with the VP (refined)
    let vanishingPoint: SIMD2<Float>?    // final (refined) VP
    let foulLineY: Int?                  // near boundary row (tracker anchor; = max yNear) — unchanged behaviour
    let satFloorUsed: Int
    let imageSize: SIMD2<Int>
    var foulLine: SIMD2<Double>? = nil        // first good lane's foul fit (c, d): y = c·x + d
    var foulCorners: [SIMD2<Double>]? = nil   // first good lane's foul × (left,right) edges — the golden anchor
    var debug: ODLaneDebug = ODLaneDebug()
    // DEC-128: ALL raw lanes at the winning floor (before the VP-consistency "good" filter). The tracker scores
    // every candidate lane by the ball track (_lane_ball_score) and picks the ball's — on a pale lane whose edges
    // skew the shared VP, the real lane can be dropped from `lanes` but is still here for the ball to be found on.
    var rawLanes: [ODDetectedLane] = []
}

// Mutable working lane during the port (Double; mirrors the `l` dict in lanes.py).
nonisolated private final class WorkLane {
    var la: Double; var lb: Double; var lres: Double
    var ra: Double; var rb: Double; var rres: Double
    var track: [(y: Int, a: Int, b: Int)]
    var yNear: Int; var yFar: Int
    var yRng0: Double { Double(yFar) }   // T[:,0].min()
    var yRng1: Double { Double(yNear) }  // T[:,0].max()
    var foulC = 0.0; var foulD = 0.0; var foulRes = 0.0; var hasFoul = false
    init(la: Double, lb: Double, lres: Double, ra: Double, rb: Double, rres: Double,
         track: [(y: Int, a: Int, b: Int)], yNear: Int, yFar: Int) {
        self.la = la; self.lb = lb; self.lres = lres; self.ra = ra; self.rb = rb; self.rres = rres
        self.track = track; self.yNear = yNear; self.yFar = yFar
    }
    func xl(_ y: Double) -> Double { la * y + lb }
    func xr(_ y: Double) -> Double { ra * y + rb }
}

enum OnDeviceLaneDetector {

    /// Detect lane geometry on a BGRA frame/plate. Mirrors find_lanes(): try saturation floors 105 → 70 → 50;
    /// the first floor that yields a VP-consistent lane wins, then foul-fit + edge-refine + VP re-solve.
    nonisolated static func detect(pixelBuffer px: CVPixelBuffer, minRun: Int = 40, minRows: Int = 120) -> ODLaneGeometry {
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        let rb = CVPixelBufferGetBytesPerRow(px)
        guard let base = CVPixelBufferGetBaseAddress(px) else {
            return ODLaneGeometry(lanes: [], vanishingPoint: nil, foulLineY: nil, satFloorUsed: 0, imageSize: [w, h])
        }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        var strictWin: [UInt8] = []; var usedS = 105
        var good: [WorkLane] = []; var lanes: [WorkLane] = []; var rawVP: SIMD2<Double>? = nil
        var nTracks = 0
        for sMin in [105, 70, 50] {
            var mask = woodMask(buf, w: w, h: h, rowBytes: rb, sMin: UInt8(sMin))
            morphologyOpenClose(&mask, w: w, h: h)
            let d = detectEdges(mask, w: w, h: h, minRun: minRun, minRows: minRows)
            if strictWin.isEmpty { strictWin = mask; lanes = d.lanes; nTracks = d.nTracks }  // keep strict for the error path
            if let vp = d.vp, !d.good.isEmpty {
                strictWin = mask; lanes = d.lanes; good = d.good; rawVP = vp; usedS = sMin; nTracks = d.nTracks
                break
            }
            if sMin == 50 { lanes = d.lanes; nTracks = d.nTracks }
        }

        var dbg = ODLaneDebug()
        dbg.maskPixels = strictWin.reduce(0) { $0 + Int($1) }
        dbg.nTracks = nTracks; dbg.nLanes = lanes.count; dbg.nGood = good.count; dbg.usedS = usedS
        if let v = rawVP {
            dbg.rawVPx = Double(v.x); dbg.rawVPy = Double(v.y)
            for l in lanes {
                let yn = Double(l.yNear)
                let lx = l.la * yn + l.lb, rx = l.ra * yn + l.rb
                let dl = abs(Double(v.x) - (l.la * Double(v.y) + l.lb))
                let dr = abs(Double(v.x) - (l.ra * Double(v.y) + l.rb))
                dbg.rawLaneInfo.append([(lx + rx) / 2, rx - lx, dl, dr])
            }
        }

        if good.isEmpty {
            // No VP-consistent lane. (Pale-lane gutter fallback NOT ported — see header.) Honest empty geometry.
            return ODLaneGeometry(lanes: lanes.map(Self.publicLane), vanishingPoint: rawVP.map { SIMD2(Float($0.x), Float($0.y)) },
                                  foulLineY: lanes.map { $0.yNear }.max(), satFloorUsed: usedS, imageSize: [w, h],
                                  debug: dbg)
        }
        // loose = lane_mask(bg, s_min=min(60, used_s)); morphology
        var loose = woodMask(buf, w: w, h: h, rowBytes: rb, sMin: UInt8(min(60, usedS)))
        morphologyOpenClose(&loose, w: w, h: h)
        dbg.loosePixels = loose.reduce(0) { $0 + Int($1) }

        return finish(good: good, raw: lanes, strict: strictWin, loose: loose, w: w, h: h, usedS: usedS, dbg: dbg)
    }

    /// Geometry-only entry for parity isolation: run the post-mask pipeline on PRE-COMPUTED 0/1 masks (the exact
    /// masks the Python reference produced), so a divergence localises to geometry vs HSV/morphology. `strict` is
    /// the winning saturation mask (tracks + foul); `loose` is s_min = min(60, used_s) (edge refine).
    nonisolated static func detect(strictMask strict: [UInt8], looseMask loose: [UInt8], w: Int, h: Int,
                                   usedS: Int = 105, minRun: Int = 40, minRows: Int = 120) -> ODLaneGeometry {
        let d = detectEdges(strict, w: w, h: h, minRun: minRun, minRows: minRows)
        var dbg = ODLaneDebug()
        dbg.maskPixels = strict.reduce(0) { $0 + Int($1) }; dbg.loosePixels = loose.reduce(0) { $0 + Int($1) }
        dbg.nTracks = d.nTracks; dbg.nLanes = d.lanes.count; dbg.nGood = d.good.count; dbg.usedS = usedS
        if let v = d.vp { dbg.rawVPx = Double(v.x); dbg.rawVPy = Double(v.y) }
        guard let _ = d.vp, !d.good.isEmpty else {
            return ODLaneGeometry(lanes: d.lanes.map(Self.publicLane), vanishingPoint: nil,
                                  foulLineY: d.lanes.map { $0.yNear }.max(), satFloorUsed: usedS, imageSize: [w, h], debug: dbg)
        }
        return finish(good: d.good, raw: d.lanes, strict: strict, loose: loose, w: w, h: h, usedS: usedS, dbg: dbg)
    }

    // MARK: finish — foul fit + edge refine + VP re-solve (find_lanes tail, lines 130-143)
    nonisolated private static func finish(good: [WorkLane], raw: [WorkLane], strict: [UInt8], loose: [UInt8],
                                           w: Int, h: Int, usedS: Int, dbg dbgIn: ODLaneDebug) -> ODLaneGeometry {
        let dbg = dbgIn
        for l in good {
            foulFit(l, mask: strict, w: w, h: h)        // _foul(l, foul_mask)
            refineEdges(l, loose: loose, w: w, h: h)    // _refine_edges(l, loose)
        }
        // re-solve VP with refined edges: single 2x2 (unweighted) for one lane, else weighted lstsq.
        let vp: SIMD2<Double>
        if good.count == 1 {
            vp = intersectEdges(good[0])
        } else {
            var edges: [(a: Double, b: Double, r: Double)] = []
            for l in good { edges.append((l.la, l.lb, l.lres)); edges.append((l.ra, l.rb, l.rres)) }
            vp = solveVPWeighted(edges) ?? intersectEdges(good[0])
        }
        let g0 = good[0]
        var geom = ODLaneGeometry(lanes: good.map(Self.publicLane),
                                  vanishingPoint: SIMD2(Float(vp.x), Float(vp.y)),
                                  foulLineY: good.map { $0.yNear }.max(), satFloorUsed: usedS, imageSize: [w, h],
                                  debug: dbg)
        if g0.hasFoul {
            geom.foulLine = SIMD2(g0.foulC, g0.foulD)
            geom.foulCorners = foulCorners(g0)
        }
        // DEC-128: expose ALL raw lanes (good + VP-rejected) so the tracker can score each by the ball track and
        // pick the ball's lane — a pale lane whose edges skew the shared VP gets dropped from `good` but the ball
        // is still on it. `publicLane` just reads the (unrefined) edges, which is all the tracker geometry needs.
        geom.rawLanes = raw.map(Self.publicLane)
        return geom
    }

    nonisolated private static func publicLane(_ l: WorkLane) -> ODDetectedLane {
        let widthNear = (l.ra * Double(l.yNear) + l.rb) - (l.la * Double(l.yNear) + l.lb)
        return ODDetectedLane(left: LaneEdge(a: Float(l.la), b: Float(l.lb), resid: Float(l.lres)),
                              right: LaneEdge(a: Float(l.ra), b: Float(l.rb), resid: Float(l.rres)),
                              yNear: l.yNear, yFar: l.yFar, widthNearPx: Float(widthNear))
    }

    // MARK: wood mask (HSV: H 5–25, S>sMin, V>70) on BGRA  (lane_mask before morphology)
    nonisolated private static func woodMask(_ buf: UnsafePointer<UInt8>, w: Int, h: Int, rowBytes: Int, sMin: UInt8) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: w * h)
        m.withUnsafeMutableBufferPointer { out in
            for y in 0..<h {
                let row = y * rowBytes
                for x in 0..<w {
                    let p = row + x * 4
                    let b = buf[p], g = buf[p + 1], r = buf[p + 2]   // BGRA
                    let (hue, sat, val) = bgrToHSV(r: r, g: g, b: b)
                    if hue >= 5 && hue <= 25 && sat > sMin && val > 70 { out[y * w + x] = 1 }
                }
            }
        }
        return m
    }

    /// OpenCV-style HSV (H in 0–180, S/V in 0–255) to match cv2.cvtColor(BGR2HSV).
    nonisolated private static func bgrToHSV(r: UInt8, g: UInt8, b: UInt8) -> (Int, Int, Int) {
        let rf = Int(r), gf = Int(g), bf = Int(b)
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), d = mx - mn
        let v = mx
        // cv2 8-bit: S = saturate(diff*255 / V); integer division (truncation), matches cv2's fixed-point.
        let s = mx == 0 ? 0 : (d * 255) / mx
        var hdeg = 0
        if d != 0 {
            if mx == rf { hdeg = (60 * (gf - bf) / d + 360) % 360 }
            else if mx == gf { hdeg = (60 * (bf - rf) / d + 120) }
            else { hdeg = (60 * (rf - gf) / d + 240) }
        }
        return (hdeg / 2, max(0, min(255, s)), v)   // H/2 → 0–180, OpenCV convention
    }

    // MARK: morphology open(5x5) then close(9x9) via vImage on the planar mask (0/255)
    nonisolated private static func morphologyOpenClose(_ m: inout [UInt8], w: Int, h: Int) {
        for i in m.indices where m[i] != 0 { m[i] = 255 }
        func morph(_ src: inout [UInt8], k: Int, dilateFirst: Bool) {
            var tmp = [UInt8](repeating: 0, count: w * h)
            src.withUnsafeMutableBufferPointer { s in
                tmp.withUnsafeMutableBufferPointer { t in
                    var inB = vImage_Buffer(data: s.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
                    var outB = vImage_Buffer(data: t.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
                    let f = vImage_Flags(kvImageEdgeExtend)
                    if dilateFirst {
                        _ = vImageMax_Planar8(&inB, &outB, nil, 0, 0, UInt(k), UInt(k), f)
                        _ = vImageMin_Planar8(&outB, &inB, nil, 0, 0, UInt(k), UInt(k), f)   // result back in src
                    } else {
                        _ = vImageMin_Planar8(&inB, &outB, nil, 0, 0, UInt(k), UInt(k), f)
                        _ = vImageMax_Planar8(&outB, &inB, nil, 0, 0, UInt(k), UInt(k), f)
                    }
                }
            }
        }
        morph(&m, k: 5, dilateFirst: false)   // open  = erode then dilate
        morph(&m, k: 9, dilateFirst: true)    // close = dilate then erode
        for i in m.indices where m[i] != 0 { m[i] = 1 }
    }

    // MARK: edge tracks + raw VP  (port of _detect)
    nonisolated private static func detectEdges(_ m: [UInt8], w: Int, h: Int, minRun: Int, minRows: Int)
        -> (lanes: [WorkLane], good: [WorkLane], vp: SIMD2<Double>?, nTracks: Int) {
        var tracks: [[(y: Int, a: Int, b: Int)]] = []
        var active: [Int] = []
        var y = h - 1
        while y > 0 {
            var runs: [(Int, Int)] = []
            var x = 0
            let rowOff = y * w
            let minLen = Double(minRun) * (0.3 + 0.7 * Double(y) / Double(h))
            while x < w {
                if m[rowOff + x] == 1 {
                    let start = x
                    while x < w && m[rowOff + x] == 1 { x += 1 }
                    if Double(x - 1 - start) >= minLen { runs.append((start, x - 1)) }
                } else { x += 1 }
            }
            var newActive: [Int] = []
            for (a, b) in runs {
                var hit: Int? = nil
                for ti in active {
                    let last = tracks[ti].last!
                    if min(b, last.b) - max(a, last.a) > Int(0.5 * Double(min(b - a, last.b - last.a))) { hit = ti; break }
                }
                let idx: Int
                if let hh = hit { idx = hh } else { tracks.append([]); idx = tracks.count - 1 }
                tracks[idx].append((y, a, b)); newActive.append(idx)
            }
            active = newActive
            y -= 2
        }
        let kept = tracks.filter { $0.count * 2 >= minRows }
        var lanes: [WorkLane] = []
        for t in kept {
            let L = t.filter { $0.a > 2 }.map { SIMD2<Double>(Double($0.a), Double($0.y)) }   // (x=a, y)
            let R = t.filter { $0.b < w - 3 }.map { SIMD2<Double>(Double($0.b), Double($0.y)) }
            if L.count < 30 || R.count < 30 { continue }
            let (pl, sl) = robustFit(L); let (pr, sr) = robustFit(R)
            let yNear = t.map { $0.y }.max()!, yFar = t.map { $0.y }.min()!
            lanes.append(WorkLane(la: pl.a, lb: pl.b, lres: sl, ra: pr.a, rb: pr.b, rres: sr, track: t, yNear: yNear, yFar: yFar))
        }
        guard !lanes.isEmpty else { return (lanes, [], nil, kept.count) }
        var edges: [(a: Double, b: Double, r: Double)] = []
        for l in lanes { edges.append((l.la, l.lb, l.lres)); edges.append((l.ra, l.rb, l.rres)) }
        guard let vp = solveVPWeighted(edges) else { return (lanes, [], nil, kept.count) }
        var good: [WorkLane] = []
        for l in lanes {
            let dl = abs(vp.x - (l.la * vp.y + l.lb))
            let dr = abs(vp.x - (l.ra * vp.y + l.rb))
            let widthNear = (l.ra * l.yRng1 + l.rb) - (l.la * l.yRng1 + l.lb)
            if max(dl, dr) < 0.08 * Double(w) && widthNear > 60 { good.append(l) }
        }
        return (lanes, good, vp, kept.count)
    }

    /// Robust x = a·y + b (iterative outlier rejection), line-for-line port of _fit. pts are (x, y). Double.
    nonisolated private static func robustFit(_ pts: [SIMD2<Double>], iters: Int = 8) -> (edge: (a: Double, b: Double), resid: Double) {
        var keep = [Bool](repeating: true, count: pts.count)
        var a = 0.0, b = 0.0
        var lastResid = 0.0
        for _ in 0..<iters {
            (a, b) = lsFit(pts, keep: keep)
            // residual over ALL points from this fit
            // std over the CURRENT keep (Python: r[keep].std() with keep from the previous iteration)
            var sum = 0.0, sumsq = 0.0, n = 0.0
            for (i, p) in pts.enumerated() where keep[i] { let r = p.x - (a * p.y + b); sum += r; sumsq += r * r; n += 1 }
            let std = n > 0 ? (sumsq / n - (sum / n) * (sum / n)).squareRoot() : 0
            let thr = max(2.5 * std, 1.5)
            for (i, p) in pts.enumerated() { keep[i] = abs(p.x - (a * p.y + b)) < thr }
        }
        // resid = r[keep].std() with the final fit + final keep
        var sum = 0.0, sumsq = 0.0, n = 0.0
        for (i, p) in pts.enumerated() where keep[i] { let r = p.x - (a * p.y + b); sum += r; sumsq += r * r; n += 1 }
        lastResid = n > 0 ? max(0, sumsq / n - (sum / n) * (sum / n)).squareRoot() : 0
        return ((a, b), lastResid)
    }

    /// Least-squares x = a·y + b over kept points (np.polyfit(y, x, 1) equivalent), Double normal equations.
    nonisolated private static func lsFit(_ pts: [SIMD2<Double>], keep: [Bool]) -> (a: Double, b: Double) {
        var sy = 0.0, sx = 0.0, syy = 0.0, sxy = 0.0, n = 0.0
        for (i, p) in pts.enumerated() where keep[i] { sy += p.y; sx += p.x; syy += p.y * p.y; sxy += p.x * p.y; n += 1 }
        let den = n * syy - sy * sy
        if abs(den) < 1e-12 { return (0, n > 0 ? sx / n : 0) }
        let a = (n * sxy - sy * sx) / den
        let b = (sx - a * sy) / n
        return (a, b)
    }

    /// Weighted least-squares VP (lstsq of A·wt, b·wt → effective weight wt²), each edge x - a·y = b.
    nonisolated private static func solveVPWeighted(_ edges: [(a: Double, b: Double, r: Double)]) -> SIMD2<Double>? {
        var m00 = 0.0, m01 = 0.0, m11 = 0.0, r0 = 0.0, r1 = 0.0
        for e in edges {
            let wt = 1 / (e.r + 0.5); let w2 = wt * wt
            let a0 = 1.0, a1 = -e.a
            m00 += w2 * a0 * a0; m01 += w2 * a0 * a1; m11 += w2 * a1 * a1
            r0 += w2 * a0 * e.b; r1 += w2 * a1 * e.b
        }
        let det = m00 * m11 - m01 * m01
        if abs(det) < 1e-12 { return nil }
        let vx = (m11 * r0 - m01 * r1) / det
        let vy = (-m01 * r0 + m00 * r1) / det
        if !vx.isFinite || !vy.isFinite { return nil }
        return SIMD2(vx, vy)
    }

    /// Single-lane VP = exact intersection of the two edge lines (x - a·y = b), matching _vp_solve(single=True).
    nonisolated private static func intersectEdges(_ l: WorkLane) -> SIMD2<Double> {
        // [1, -la][vx]   [lb]
        // [1, -ra][vy] = [rb]
        let det = (-l.ra) - (-l.la)   // 1*(-ra) - (-la)*1
        if abs(det) < 1e-12 { return SIMD2(l.lb, 0) }
        let vx = ((-l.ra) * l.lb - (-l.la) * l.rb) / det
        let vy = (l.rb - l.lb) / det
        return SIMD2(vx, vy)
    }

    // MARK: foul line  (port of _foul)
    nonisolated private static func foulFit(_ l: WorkLane, mask m: [UInt8], w: Int, h: Int) {
        var ptsX: [Double] = []; var ptsY: [Double] = []
        let y0 = Int(l.yRng0 + 0.5 * (l.yRng1 - l.yRng0))
        let step = (0.9 - 0.1) / 40.0
        for i in 0...40 {
            let f = 0.1 + Double(i) * step
            var lastX = 0, lastY = 0; var haveLast = false; var gap = 0
            var y = y0
            while y < h {
                let xd = (l.xl(Double(y)) + f * (l.xr(Double(y)) - l.xl(Double(y)))).rounded(.toNearestOrEven)
                let x = Int(xd)
                if !(0 <= x && x < w) { break }
                if m[y * w + x] != 0 { lastX = x; lastY = y; haveLast = true; gap = 0 }
                else {
                    gap += 1
                    if haveLast && gap > 25 { break }
                }
                y += 1
            }
            if haveLast && lastY < h - 3 { ptsX.append(Double(lastX)); ptsY.append(Double(lastY)) }
        }
        guard ptsX.count >= 6 else { return }   // FOUL_LINE_NOT_IN_VIEW in Python; here leave hasFoul=false
        // robust y = c·x + d  (polyfit(x, y, 1))
        var keep = [Bool](repeating: true, count: ptsX.count)
        var c = 0.0, dd = 0.0
        for _ in 0..<8 {
            (c, dd) = lsFitXY(ptsX, ptsY, keep: keep)
            var sum = 0.0, sumsq = 0.0, n = 0.0
            for i in ptsX.indices where keep[i] { let r = ptsY[i] - (c * ptsX[i] + dd); sum += r; sumsq += r * r; n += 1 }
            let std = n > 0 ? max(0, sumsq / n - (sum / n) * (sum / n)).squareRoot() : 0
            let thr = max(2.5 * std, 2)
            var newKeep = [Bool](repeating: false, count: ptsX.count); var kn = 0
            for i in ptsX.indices { let r = ptsY[i] - (c * ptsX[i] + dd); if abs(r) < thr { newKeep[i] = true; kn += 1 } }
            if kn < 2 {
                // don't let the trim collapse the fit: re-threshold on the full-set std, then stop
                var s2 = 0.0, ss2 = 0.0
                for i in ptsX.indices { let r = ptsY[i] - (c * ptsX[i] + dd); s2 += r; ss2 += r * r }
                let n2 = Double(ptsX.count)
                let std2 = max(0, ss2 / n2 - (s2 / n2) * (s2 / n2)).squareRoot()
                let thr2 = max(2.5 * std2, 2)
                for i in ptsX.indices { let r = ptsY[i] - (c * ptsX[i] + dd); keep[i] = abs(r) < thr2 }
                break
            }
            keep = newKeep
        }
        var sum = 0.0, sumsq = 0.0, n = 0.0
        for i in ptsX.indices where keep[i] { let r = ptsY[i] - (c * ptsX[i] + dd); sum += r; sumsq += r * r; n += 1 }
        l.foulC = c; l.foulD = dd
        l.foulRes = n > 0 ? max(0, sumsq / n - (sum / n) * (sum / n)).squareRoot() : 0
        l.hasFoul = true
    }

    /// Least-squares y = c·x + d over kept points (np.polyfit(x, y, 1)).
    nonisolated private static func lsFitXY(_ xs: [Double], _ ys: [Double], keep: [Bool]) -> (c: Double, d: Double) {
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, n = 0.0
        for i in xs.indices where keep[i] { sx += xs[i]; sy += ys[i]; sxx += xs[i] * xs[i]; sxy += xs[i] * ys[i]; n += 1 }
        let den = n * sxx - sx * sx
        if abs(den) < 1e-12 { return (0, n > 0 ? sy / n : 0) }
        let c = (n * sxy - sx * sy) / den
        let d = (sy - c * sx) / n
        return (c, d)
    }

    nonisolated private static func foulCorners(_ l: WorkLane) -> [SIMD2<Double>] {
        let c = l.foulC, d = l.foulD
        var out: [SIMD2<Double>] = []
        for (a, b) in [(l.la, l.lb), (l.ra, l.rb)] {
            let y = (c * b + d) / (1 - c * a)
            out.append(SIMD2(a * y + b, y))
        }
        return out
    }

    // MARK: edge refinement  (port of _refine_edges)
    nonisolated private static func refineEdges(_ l: WorkLane, loose: [UInt8], w: Int, h: Int) {
        let fc = foulCorners(l); let yFoul = max(fc[0].y, fc[1].y)
        var cen: [Int: Double] = [:]
        for (y, a, b) in l.track { cen[y] = (Double(a) + Double(b)) / 2 }
        for it in 0..<3 {
            var L: [SIMD2<Double>] = []; var R: [SIMD2<Double>] = []
            var y = Int(yFoul) - 4
            let yStop = Int(l.yRng0) - 250   // range(.., int(y_rng[0])-250, -2)
            while y > yStop {
                if y < 0 { break }
                if y >= h { y -= 2; continue }
                let xa = l.xl(Double(y)), xb = l.xr(Double(y))
                let xcD = (it == 0 ? (cen[y] ?? (xa + xb) / 2) : (xa + xb) / 2)
                let xc = Int(xcD)
                if !(0 < xc && xc < w - 1) || loose[y * w + xc] == 0 { y -= 2; continue }
                var a = xc; while a > 0 && loose[y * w + (a - 1)] != 0 { a -= 1 }
                var b = xc; while b < w - 1 && loose[y * w + (b + 1)] != 0 { b += 1 }
                let tol = it == 0 ? Double.infinity : 0.1 * (xb - xa) + 3
                if a > 1 && abs(Double(a) - xa) < tol { L.append(SIMD2(Double(a), Double(y))) }
                if b < w - 2 && abs(Double(b) - xb) < tol { R.append(SIMD2(Double(b), Double(y))) }
                y -= 2
            }
            if L.count > 30 { let (p, s) = robustFit(L); l.la = p.a; l.lb = p.b; l.lres = s }
            if R.count > 30 { let (p, s) = robustFit(R); l.ra = p.a; l.rb = p.b; l.rres = s }
        }
    }

    // MARK: convenience — grab a steady frame from a clip for a standalone run
    nonisolated static func referenceFrame(url: URL, at index: Int = 30) -> CVPixelBuffer? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = true
        reader.add(out); reader.startReading()
        var i = 0
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if i >= index, let px = CMSampleBufferGetImageBuffer(sb) { return px }
            i += 1
        }
        return nil
    }
}
