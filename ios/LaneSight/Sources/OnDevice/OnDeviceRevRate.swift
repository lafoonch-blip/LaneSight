import Foundation
import AVFoundation
import CoreVideo

// DEC-117 — on-device REV RATE, ported from lanesight_core/cv/revrate.py (ball_crops → rev_rate). SHADOW until
// the DEC-117 promotion gate (speed within 0.3 mph of truth, rev within the server's band) passes on a real
// iPhone. The ball's surface pattern repeats once per revolution: take scale-normalised circular-masked ball
// crops along the track, build the appearance self-similarity vs time lag (autocorrelation), find the spin
// period (with harmonics), refine by long-baseline phase coherence. Returns lane rpm + an honest ± band.
//
// NOTE (compile/validation pending): this file follows the numpy reference line-for-line; it has NOT been built
// in Xcode or validated on device yet. Wire it from OnDeviceShadow and verify against the server rev band +
// the `rev_truth` 240 fps label task before trusting it. Crops are read COLOUR (hue/sat) so it needs a BGRA
// decode pass over the ball frames (separate from OnDeviceTracker's luma pass).

struct RevEstimate: Equatable {
    let rpm: Float?
    let sigmaRpm: Float?        // ± band: rpm²·dt/60 — halves at 120 fps, quarters at 240
    let nRev: Float?            // revolutions observed (for future weighting)
    let fps: Float?
    let basis: String           // "best_effort" | "unavailable"
    let note: String
}

enum OnDeviceRevRate {

    /// rev rate from ball crops along the track. `cropSize`=64, band 4–10 rev/s (matches the Python reference).
    nonisolated static func measure(url: URL, track: [TrackPoint], geo: ODLaneGeometry,
                                    cropSize: Int = 64, maxN: Int = 60,
                                    fmin: Float = 4.0, fmax: Float = 10.0) -> RevEstimate {
        func fail(_ m: String) -> RevEstimate { RevEstimate(rpm: nil, sigmaRpm: nil, nRev: nil, fps: nil, basis: "unavailable", note: m) }
        guard let lane = geo.lanes.first else { return fail("no lane geometry") }
        let pts = Array(track.sorted { $0.i < $1.i }.prefix(maxN))
        guard pts.count >= 12 else { return fail("too few ball crops for a spin period (\(pts.count))") }

        // 1) collect colour ball crops at the track points (BGRA decode; crop around the ball, resize to cropSize).
        let want: [Int: TrackPoint] = Dictionary(uniqueKeysWithValues: pts.map { ($0.i, $0) })
        var crops: [(t: Double, hs: [Float])] = []       // hue+sat, z-normalised over the inner disc
        // circular inner-disc mask (r < 0.38·size) — avoids the crop edge / background.
        var maskIdx: [Int] = []; let c = Float(cropSize - 1) / 2; let r2 = (0.38 * Float(cropSize)) * (0.38 * Float(cropSize))
        for y in 0..<cropSize { for x in 0..<cropSize {
            let dx = Float(x) - c, dy = Float(y) - c
            if dx*dx + dy*dy < r2 { maskIdx.append(y*cropSize + x) }
        } }

        let asset = AVURLAsset(url: url)
        guard let vtrack = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
            return fail("reader unavailable")
        }
        let out = AVAssetReaderTrackOutput(track: vtrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false; reader.add(out); reader.startReading()
        var i = 0
        let maxI = pts.map { $0.i }.max() ?? 0
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if i > maxI { break }
            defer { i += 1 }
            guard let p = want[i], let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if let hs = cropHueSat(px, cx: p.cx, cy: p.contactRow, diamFrac: p.frac, lane: lane,
                                   size: cropSize, maskIdx: maskIdx) {
                crops.append((t, hs))
            }
        }
        reader.cancelReading()
        guard crops.count >= 12 else { return fail("too few valid ball crops (\(crops.count))") }

        // 2) self-similarity matrix sim = V·Vᵀ / dim  (V rows already z-normalised over the disc).
        let m = crops.count, dim = crops[0].hs.count
        var sim = [Float](repeating: 0, count: m * m)
        for a in 0..<m { for b in a..<m {
            var s: Float = 0; let va = crops[a].hs, vb = crops[b].hs
            for k in 0..<dim { s += va[k] * vb[k] }
            s /= Float(dim); sim[a*m+b] = s; sim[b*m+a] = s
        } }
        let ts = crops.map { $0.t }
        let dt = median(diff(ts))
        guard dt > 1e-6 else { return fail("degenerate timestamps") }

        // 3) autocorrelation over lags (mean of each off-diagonal), then period search with harmonics 1,2,3.
        let nLag = m / 2
        guard nLag >= 2 else { return fail("track too short for autocorrelation") }
        let lags = Array(1..<nLag)
        var ac = [Float](repeating: 0, count: lags.count)
        for (li, k) in lags.enumerated() {
            var s: Float = 0; var cnt = 0
            for a in 0..<(m - k) { s += sim[a*m + (a+k)]; cnt += 1 }
            ac[li] = cnt > 0 ? s / Float(cnt) : .nan
        }
        let lagF = lags.map { Float($0) }
        let nP = 400
        var periods = [Float](repeating: 0, count: nP)
        for j in 0..<nP { periods[j] = (1/fmax) + (1/fmin - 1/fmax) * Float(j)/Float(nP - 1) }
        var score = [Float](repeating: -.infinity, count: nP)
        var valid = [Bool](repeating: false, count: nP)
        for (j, P) in periods.enumerated() {
            let k = P / Float(dt)
            var acc: Float = 0; var cnt = 0
            for mh in [Float(1), 2, 3] where mh * k < lagF.last! { acc += interp(mh * k, lagF, ac); cnt += 1 }
            if cnt > 0 { let v = acc / Float(cnt); if v.isFinite { score[j] = v; valid[j] = true } }
        }
        guard valid.contains(true) else { return fail("no spin pattern resolved") }
        let lastValid = valid.lastIndex(of: true)!
        var ai = 0; var bestv = -Float.infinity
        for j in 0..<nP where valid[j] && score[j] > bestv { bestv = score[j]; ai = j }
        let atRail = ai < 3 || ai > lastValid - 3
        if atRail { return fail("spin period at the search rail — pattern doesn't repeat cleanly") }

        var P = periods[ai]; var f0 = 1/P
        // 4) phase-coherence refine over all crop pairs, narrow window around the coarse seed (no harmonic jumps).
        var dTs: [Float] = []; var sp: [Float] = []
        for a in 0..<m { for b in (a+1)..<m { dTs.append(Float(ts[b]-ts[a])); sp.append(sim[a*m+b]) } }
        let spMean = sp.reduce(0,+)/Float(sp.count); for k in 0..<sp.count { sp[k] -= spMean }
        let nW = 600; var bestf = f0; var bestpw = -Float.infinity
        for j in 0..<nW {
            let fw = f0*0.85 + (f0*1.15 - f0*0.85)*Float(j)/Float(nW-1)
            var pw: Float = 0; for k in 0..<sp.count { pw += sp[k] * cos(2 * .pi * fw * dTs[k]) }
            if pw > bestpw { bestpw = pw; bestf = fw }
        }
        f0 = bestf; P = 1/f0
        let rev = 60 / P
        let sigma = rev * rev * Float(dt) / 60
        let span = Float(ts.last! - ts.first!); let nRev = P > 0 ? span / P : 0
        return RevEstimate(rpm: rev, sigmaRpm: sigma, nRev: nRev, fps: Float(1/dt), basis: "best_effort",
                           note: "appearance-periodicity (hue/sat autocorr + phase refine); ±\(Int(sigma)) rpm at \(Int(1/dt)) fps")
    }

    // crop a `size`×`size` colour patch centred on the ball and return z-normalised (hue, sat) over the disc.
    nonisolated private static func cropHueSat(_ px: CVPixelBuffer, cx: Float, cy: Float, diamFrac: Float,
                                               lane: ODDetectedLane, size: Int, maskIdx: [Int]) -> [Float]? {
        // ball diameter in px at this row = BALL_IN/LANE_IN · lane width(row)
        let wl = lane.left.a * cy + lane.left.b, wr = lane.right.a * cy + lane.right.b
        let D = (8.5 / 41.5) * (wr - wl)
        if D < 6 { return nil }
        let x0 = Int(cx - 0.5 * D), y0 = Int(cy - 0.5 * D), dd = Int(D)
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let W = CVPixelBufferGetWidth(px), H = CVPixelBufferGetHeight(px), rb = CVPixelBufferGetBytesPerRow(px)
        if x0 < 0 || y0 < 0 || x0 + dd >= W || y0 + dd >= H || dd < 6 { return nil }
        guard let base = CVPixelBufferGetBaseAddress(px)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        // nearest-neighbour resample dd×dd -> size×size, convert BGRA -> (hue, sat)
        var hue = [Float](repeating: 0, count: size*size), sat = [Float](repeating: 0, count: size*size)
        for oy in 0..<size { for ox in 0..<size {
            let sx = x0 + ox * dd / size, sy = y0 + oy * dd / size
            let o = sy * rb + sx * 4
            let b = Float(base[o]), g = Float(base[o+1]), r = Float(base[o+2])
            let (h, s) = hsFrom(r: r, g: g, b: b)
            hue[oy*size+ox] = h; sat[oy*size+ox] = s
        } }
        // z-normalise hue and sat over the disc, concatenate (matches revrate.py's hue/sat channel stack).
        func znorm(_ v: [Float]) -> [Float] {
            let m = maskIdx.map { v[$0] }; let mean = m.reduce(0,+)/Float(m.count)
            let sd = sqrt(m.map { ($0-mean)*($0-mean) }.reduce(0,+)/Float(m.count)) + 1e-6
            return m.map { ($0 - mean)/sd }
        }
        return znorm(hue) + znorm(sat)
    }

    // BGR -> OpenCV-style HSV hue (0..180) + saturation (0..255), matching cv2.cvtColor(.,BGR2HSV).
    nonisolated private static func hsFrom(r: Float, g: Float, b: Float) -> (Float, Float) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let s = mx <= 0 ? 0 : d / mx * 255
        var h: Float = 0
        if d > 0 {
            if mx == r { h = 30 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 + 30 * ((b - r) / d) }
            else { h = 120 + 30 * ((r - g) / d) }
            if h < 0 { h += 180 }
        }
        return (h, s)
    }

    nonisolated private static func diff(_ a: [Double]) -> [Double] { zip(a.dropFirst(), a).map { $0 - $1 } }
    nonisolated private static func median(_ a: [Double]) -> Double {
        let s = a.sorted(); return s.isEmpty ? 0 : s[s.count/2]
    }
    // linear interpolation of ac at fractional lag x over integer lags lagF (like np.interp, clamped at ends).
    nonisolated private static func interp(_ x: Float, _ xp: [Float], _ fp: [Float]) -> Float {
        if x <= xp.first! { return fp.first! }
        if x >= xp.last! { return fp.last! }
        var lo = 0, hi = xp.count - 1
        while hi - lo > 1 { let mid = (lo+hi)/2; if xp[mid] <= x { lo = mid } else { hi = mid } }
        let t = (x - xp[lo]) / (xp[hi] - xp[lo]); return fp[lo] + t * (fp[hi] - fp[lo])
    }
}
