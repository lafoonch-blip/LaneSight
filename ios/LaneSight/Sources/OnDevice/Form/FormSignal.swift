import Foundation

/// Numeric primitives ported 1:1 from the numpy usage in `lanesight_core/form/pose.py` so the on-device event
/// detection reproduces the reference bit-for-bit given the same landmarks. Everything is Double; NaN carries the
/// "not measured / not visible" meaning exactly as in the reference.
nonisolated enum FormSignal {
    static let MIN_VIS = 0.3                 // landmark visibility floor (pose.MIN_VIS)
    static let POSE_SKELETON_VIS = 0.65

    // MARK: scalar reductions
    static func median(_ a: [Double]) -> Double {
        let v = a.filter { !$0.isNaN }.sorted()
        if v.isEmpty { return Double.nan }
        let n = v.count
        return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0   // numpy median averages the middle pair
    }
    static func nanmean(_ a: [Double]) -> Double {
        var s = 0.0, c = 0
        for x in a where !x.isNaN { s += x; c += 1 }
        return c == 0 ? Double.nan : s / Double(c)
    }
    static func nanmax(_ a: [Double]) -> Double {
        var m = -Double.infinity, any = false
        for x in a where !x.isNaN { if x > m { m = x }; any = true }
        return any ? m : Double.nan
    }
    static func nanmin(_ a: [Double]) -> Double {
        var m = Double.infinity, any = false
        for x in a where !x.isNaN { if x < m { m = x }; any = true }
        return any ? m : Double.nan
    }
    static func argmin(_ a: [Double]) -> Int {
        var bi = 0, bv = Double.infinity
        for (i, x) in a.enumerated() where x < bv { bv = x; bi = i }
        return bi
    }
    static func argmax(_ a: [Double]) -> Int {
        var bi = 0, bv = -Double.infinity
        for (i, x) in a.enumerated() where x > bv { bv = x; bi = i }
        return bi
    }

    static func nanToNum(_ a: [Double], nan: Double) -> [Double] { a.map { $0.isNaN ? nan : $0 } }
    /// np.fmax on two already-nan-filled arrays = element-wise max.
    static func fmax(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map { Swift.max($0, $1) }
    }

    /// np.searchsorted(side='left'): first index i with a[i] >= v (a sorted ascending).
    static func searchsorted(_ a: [Double], _ v: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < v { lo = m + 1 } else { hi = m } }
        return lo
    }

    /// np.interp(x, xp, fp): linear interpolation with flat extrapolation at the ends. xp ascending.
    static func interp(_ x: [Double], _ xp: [Double], _ fp: [Double]) -> [Double] {
        guard !xp.isEmpty else { return x.map { _ in Double.nan } }
        return x.map { xi in
            if xi <= xp[0] { return fp[0] }
            if xi >= xp[xp.count - 1] { return fp[fp.count - 1] }
            var lo = 0, hi = xp.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if xp[m] <= xi { lo = m } else { hi = m } }
            let t = (xi - xp[lo]) / (xp[hi] - xp[lo])
            return fp[lo] + t * (fp[hi] - fp[lo])
        }
    }

    /// np.gradient(f, t), edge_order=1: second-order central differences in the interior with non-uniform
    /// spacing, first-order one-sided at the two boundaries. NaNs must be filled by the caller (as in _speed).
    static func gradient(_ f: [Double], _ t: [Double]) -> [Double] {
        let n = f.count
        if n < 2 { return [Double](repeating: 0, count: n) }
        var g = [Double](repeating: 0, count: n)
        g[0] = (f[1] - f[0]) / (t[1] - t[0])
        g[n - 1] = (f[n - 1] - f[n - 2]) / (t[n - 1] - t[n - 2])
        for i in 1..<(n - 1) {
            let dx1 = t[i] - t[i - 1]       // hs
            let dx2 = t[i + 1] - t[i]       // hd
            let a = -dx2 / (dx1 * (dx1 + dx2))
            let b = (dx2 - dx1) / (dx1 * dx2)
            let c = dx1 / (dx2 * (dx1 + dx2))
            g[i] = a * f[i - 1] + b * f[i] + c * f[i + 1]
        }
        return g
    }

    // MARK: pose.py helpers

    /// _smooth(a, w): NaN-aware centered moving average of width w.
    static func smooth(_ a: [Double], _ w: Int) -> [Double] {
        let n = a.count
        var out = [Double](repeating: Double.nan, count: n)
        for i in 0..<n {
            let lo = Swift.max(0, i - w / 2)
            let hi = Swift.min(n, i + w / 2 + 1)
            var s = 0.0, c = 0
            for j in lo..<hi where !a[j].isNaN { s += a[j]; c += 1 }
            if c > 0 { out[i] = s / Double(c) }
        }
        return out
    }

    /// _point(lms, idxs, axis): visibility-weighted series of one coordinate (axis 0=x,1=y) fused over indices.
    /// `lm` is per-frame [33][5]; returns one Double per frame.
    static func point(_ frames: [FormPoseLandmarker.Frame], _ idxs: [Int], axis: Int) -> [Double] {
        let n = frames.count
        var out = [Double](repeating: Double.nan, count: n)
        for i in 0..<n {
            let row = frames[i].lm
            var num = 0.0, wsum = 0.0
            for k in idxs {
                let v = Double(row[k][3])          // visibility
                let c = Double(row[k][axis])
                let ok = (v > MIN_VIS) && !c.isNaN
                if ok { num += c * v; wsum += v }
            }
            if wsum >= MIN_VIS { out[i] = num / Swift.max(wsum, 1e-6) }
            // else stays NaN (matches out[w < MIN_VIS] = nan)
        }
        return out
    }

    /// _torso(lms): median |hip_y - shoulder_y|, fallback 0.2.
    static func torso(_ frames: [FormPoseLandmarker.Frame]) -> Double {
        let sho = point(frames, [FormPoseLandmarker.LM.lShoulder, FormPoseLandmarker.LM.rShoulder], axis: 1)
        let hip = point(frames, [FormPoseLandmarker.LM.lHip, FormPoseLandmarker.LM.rHip], axis: 1)
        var d = [Double]()
        for i in 0..<sho.count {
            let v = abs(hip[i] - sho[i])
            if !v.isNaN { d.append(v) }
        }
        let m = median(d)
        return (d.isEmpty || m.isNaN) ? 0.2 : m
    }

    /// _speed(x, y, t): fill NaNs with the series mean, then smoothed hypot of the two gradients (w=5).
    static func speed(_ x: [Double], _ y: [Double], _ t: [Double]) -> [Double] {
        let mx = x.contains { !$0.isNaN } ? nanmean(x) : 0.0
        let my = y.contains { !$0.isNaN } ? nanmean(y) : 0.0
        let xf = x.map { $0.isNaN ? mx : $0 }
        let yf = y.map { $0.isNaN ? my : $0 }
        let gx = gradient(xf, t)
        let gy = gradient(yf, t)
        var h = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count { h[i] = Foundation.hypot(gx[i], gy[i]) }
        return smooth(h, 5)
    }

    /// _local_minima(sig, t, sep_s, max_frac): indices of local minima separated by ≥ sep_s, below a fraction
    /// of the signal range.
    static func localMinima(_ sig: [Double], _ t: [Double], sepS: Double, maxFrac: Double = 0.65) -> [Int] {
        let filled = sig.contains { !$0.isNaN } ? nanmax(sig) : 1.0
        let s = sig.map { $0.isNaN ? filled : $0 }
        let dt = medianDiff(t)
        let w = Swift.max(1, Int(sepS / dt))
        let lo = s.min() ?? 0, hi = s.max() ?? 1
        let thr = lo + maxFrac * (hi - lo)
        var out = [Int]()
        for i in 0..<s.count {
            let a = Swift.max(0, i - w), b = Swift.min(s.count, i + w + 1)
            let segMin = s[a..<b].min() ?? s[i]
            if s[i] == segMin && s[i] < thr {
                if out.isEmpty || (i - out[out.count - 1]) >= w { out.append(i) }
                else if s[i] < s[out[out.count - 1]] { out[out.count - 1] = i }
            }
        }
        return out
    }

    /// _local_extrema(y, t, sep_s): (maxima, minima) indices, each separated by ≥ sep_s.
    static func localExtrema(_ y: [Double], _ t: [Double], sepS: Double) -> (mx: [Int], mn: [Int]) {
        let dt = medianDiff(t)
        let w = Swift.max(1, Int(sepS / dt))
        var mx = [Int](), mn = [Int]()
        for i in 0..<y.count {
            let a = Swift.max(0, i - w), b = Swift.min(y.count, i + w + 1)
            let segMax = y[a..<b].max() ?? y[i]
            let segMin = y[a..<b].min() ?? y[i]
            if y[i] == segMax && (mx.isEmpty || i - mx[mx.count - 1] >= w) { mx.append(i) }
            if y[i] == segMin && (mn.isEmpty || i - mn[mn.count - 1] >= w) { mn.append(i) }
        }
        return (mx, mn)
    }

    static func medianDiff(_ t: [Double]) -> Double {
        guard t.count > 1 else { return 1.0 / 30.0 }
        var d = [Double]()
        for i in 1..<t.count { d.append(t[i] - t[i - 1]) }
        let m = median(d)
        return m > 1e-9 ? m : 1.0 / 30.0
    }
}
