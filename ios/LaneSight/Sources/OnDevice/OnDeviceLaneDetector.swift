import Foundation
import AVFoundation
import Accelerate
import CoreVideo

// DEC-102/103 — Phase 3, stage 2 (SHADOW, FIRST PASS). On-device lane geometry, ported faithfully from
// lanesight_core/cv/lanes.py: saturated-wood HSV mask → morphology → per-row wood runs linked into edge
// tracks → robust edge lines (x = a·y + b) → one shared vanishing point; foul line = the mask's near boundary.
// Runs on a steady frame (stage-1 reference). Output is the lane coordinate basis every metric reads.
//
// FIRST PASS: compiles + runs; the thresholds/robustness need tuning against real clips (run it from the dev
// panel and eyeball the detected edges/VP). SHADOW — never shown or counted. Metric-level parity (DEC-103).

struct LaneEdge: Equatable { let a: Float; let b: Float; let resid: Float }   // x = a*y + b
struct ODDetectedLane: Equatable {
    let left: LaneEdge; let right: LaneEdge
    let yNear: Int; let yFar: Int
    let widthNearPx: Float
}
struct ODLaneGeometry: Equatable {
    let lanes: [ODDetectedLane]      // lanes agreeing with the VP
    let vanishingPoint: SIMD2<Float>?
    let foulLineY: Int?
    let satFloorUsed: Int
    let imageSize: SIMD2<Int>
}

enum OnDeviceLaneDetector {

    /// Detect lane geometry on a BGRA frame. Mirrors find_lanes(): try saturation floors 105 → 70 → 50.
    nonisolated static func detect(pixelBuffer px: CVPixelBuffer, minRun: Int = 40, minRows: Int = 120) -> ODLaneGeometry {
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        let rb = CVPixelBufferGetBytesPerRow(px)
        guard let base = CVPixelBufferGetBaseAddress(px) else {
            return ODLaneGeometry(lanes: [], vanishingPoint: nil, foulLineY: nil, satFloorUsed: 0, imageSize: [w, h])
        }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        for sMin in [105, 70, 50] {
            var mask = woodMask(buf, w: w, h: h, rowBytes: rb, sMin: UInt8(sMin))
            morphologyOpenClose(&mask, w: w, h: h)
            let (lanes, good, vp) = detectEdges(mask, w: w, h: h, minRun: minRun, minRows: minRows)
            if let vp, !good.isEmpty {
                let foul = good.map { $0.yNear }.max()
                return ODLaneGeometry(lanes: good, vanishingPoint: vp, foulLineY: foul, satFloorUsed: sMin, imageSize: [w, h])
            }
            if sMin == 50 {   // last pass: return whatever we have, honestly (may be empty = LANE_GEOMETRY_UNUSABLE)
                let foul = lanes.map { $0.yNear }.max()
                return ODLaneGeometry(lanes: lanes, vanishingPoint: vp, foulLineY: foul, satFloorUsed: sMin, imageSize: [w, h])
            }
        }
        return ODLaneGeometry(lanes: [], vanishingPoint: nil, foulLineY: nil, satFloorUsed: 50, imageSize: [w, h])
    }

    // MARK: wood mask (HSV: H 5–25, S>sMin, V>70) on BGRA
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
    nonisolated private static func bgrToHSV(r: UInt8, g: UInt8, b: UInt8) -> (UInt8, UInt8, UInt8) {
        let rf = Int(r), gf = Int(g), bf = Int(b)
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), d = mx - mn
        let v = mx
        let s = mx == 0 ? 0 : (d * 255) / mx
        var hdeg = 0
        if d != 0 {
            if mx == rf { hdeg = (60 * (gf - bf) / d + 360) % 360 }
            else if mx == gf { hdeg = (60 * (bf - rf) / d + 120) }
            else { hdeg = (60 * (rf - gf) / d + 240) }
        }
        return (UInt8(hdeg / 2), UInt8(max(0, min(255, s))), UInt8(v))   // H/2 → 0–180, OpenCV convention
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

    // MARK: edge tracks + VP (port of _detect)
    nonisolated private static func detectEdges(_ m: [UInt8], w: Int, h: Int, minRun: Int, minRows: Int)
        -> ([ODDetectedLane], [ODDetectedLane], SIMD2<Float>?) {
        // tracks: each a list of (y, aRun, bRun) = left/right x of the wood run on that row
        var tracks: [[(y: Int, a: Int, b: Int)]] = []
        var active: [Int] = []   // indices into tracks
        var y = h - 1
        while y > 0 {
            // runs of 1s on row y
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
        var lanes: [ODDetectedLane] = []
        for t in tracks where t.count * 2 >= minRows {
            let L = t.filter { $0.a > 2 }.map { (SIMD2<Float>(Float($0.a), Float($0.y))) }
            let R = t.filter { $0.b < w - 3 }.map { (SIMD2<Float>(Float($0.b), Float($0.y))) }
            if L.count < 30 || R.count < 30 { continue }
            let (pl, sl) = robustFit(L); let (pr, sr) = robustFit(R)
            let yNear = t.map { $0.y }.max()!, yFar = t.map { $0.y }.min()!
            let widthNear = (pr.a * Float(yNear) + pr.b) - (pl.a * Float(yNear) + pl.b)
            lanes.append(ODDetectedLane(left: LaneEdge(a: pl.a, b: pl.b, resid: sl),
                                      right: LaneEdge(a: pr.a, b: pr.b, resid: sr),
                                      yNear: yNear, yFar: yFar, widthNearPx: widthNear))
        }
        guard !lanes.isEmpty else { return (lanes, [], nil) }
        // VP from all edges: x - a*y = b, weighted by 1/(resid+0.5)
        var edges: [(a: Float, b: Float, r: Float)] = []
        for l in lanes { edges.append((l.left.a, l.left.b, l.left.resid)); edges.append((l.right.a, l.right.b, l.right.resid)) }
        guard let vp = solveVP(edges) else { return (lanes, [], nil) }
        var good: [ODDetectedLane] = []
        for l in lanes {
            let dl = abs(vp.x - (l.left.a * vp.y + l.left.b))
            let dr = abs(vp.x - (l.right.a * vp.y + l.right.b))
            if max(dl, dr) < 0.08 * Float(w) && l.widthNearPx > 60 { good.append(l) }
        }
        return (lanes, good, vp)
    }

    /// Robust x = a*y + b (iterative outlier rejection), port of _fit. pts are (x, y).
    nonisolated private static func robustFit(_ pts: [SIMD2<Float>], iters: Int = 8) -> (edge: (a: Float, b: Float), resid: Float) {
        var keep = [Bool](repeating: true, count: pts.count)
        var a: Float = 0, b: Float = 0, resid: Float = 0
        for _ in 0..<iters {
            // least squares x = a*y + b over kept points
            var sy: Float = 0, sx: Float = 0, syy: Float = 0, sxy: Float = 0; var n: Float = 0
            for (i, p) in pts.enumerated() where keep[i] { sy += p.y; sx += p.x; syy += p.y*p.y; sxy += p.x*p.y; n += 1 }
            let den = n*syy - sy*sy
            if abs(den) < 1e-6 { break }
            a = (n*sxy - sy*sx) / den; b = (sx - a*sy) / n
            // residual std over kept
            var ss: Float = 0, cnt: Float = 0
            for (i, p) in pts.enumerated() where keep[i] { let r = p.x - (a*p.y + b); ss += r*r; cnt += 1 }
            let std = cnt > 0 ? (ss/cnt).squareRoot() : 0
            resid = std
            let thr = max(2.5 * std, 1.5)
            for (i, p) in pts.enumerated() { keep[i] = abs(p.x - (a*p.y + b)) < thr }
        }
        return ((a, b), resid)
    }

    /// Weighted least-squares vanishing point: each edge x - a*y = b. Solve [1, -a]·[vx, vy] = b.
    nonisolated private static func solveVP(_ edges: [(a: Float, b: Float, r: Float)]) -> SIMD2<Float>? {
        // Normal equations for 2 unknowns: A = [[1, -a]], weighted.
        var m00: Float = 0, m01: Float = 0, m11: Float = 0, r0: Float = 0, r1: Float = 0
        for e in edges {
            let wt = 1 / (e.r + 0.5)
            let a0: Float = 1, a1 = -e.a
            m00 += wt*a0*a0; m01 += wt*a0*a1; m11 += wt*a1*a1
            r0 += wt*a0*e.b; r1 += wt*a1*e.b
        }
        let det = m00*m11 - m01*m01
        if abs(det) < 1e-6 { return nil }
        let vx = ( m11*r0 - m01*r1) / det
        let vy = (-m01*r0 + m00*r1) / det
        if !vx.isFinite || !vy.isFinite { return nil }
        return SIMD2<Float>(vx, vy)
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
