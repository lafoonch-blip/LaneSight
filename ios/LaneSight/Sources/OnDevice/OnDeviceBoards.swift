import Foundation

// DEC-127 — on-device BOARD metrics. Faithful port of lanesight_core/cv/metrics.py `compute(...)`: build a
// lane-plane homography (image → X inches from the left edge, Z feet from the foul line), map the ball track
// into it, then read the board metrics off a LOESS board-vs-distance curve. Boards are 1..39 absolute
// (board 1 = right gutter). Honesty (DEC-127): a board we can actually measure from THIS shot is `ok` (counts
// for the Score); one the track doesn't support (not tracked to the pins / through the mid lane / to the foul)
// is `unavailable` + a reason — never a fabricated number. The validation clips are a dev gate, not runtime.
//
// Why a homography and not the raw image fraction: the lateral image fraction keystones under perspective, so
// reading a board straight off it can be 1-2 boards wrong — and a 2-board entry error flips pocket/light/high
// advice (CLAUDE.md). The homography rectifies both the lateral position (X) and the down-lane depth (Z) from
// the detected lane quad, exactly as the server does.

private nonisolated(unsafe) let B_LANE_IN: Double = 41.5
private nonisolated(unsafe) let B_BOARDS: Double = 39
private nonisolated(unsafe) let B_Z_IMPACT: Double = 59.44   // ball centre at first head-pin contact

/// One board metric: a value with an honest status + reason (mirrors the server Measurement contract).
nonisolated struct BoardCell: Equatable {
    let value: Double?
    let status: String   // "ok" | "unavailable"
    let note: String?
    static func ok(_ v: Double) -> BoardCell { BoardCell(value: v, status: "ok", note: nil) }
    static func na(_ why: String) -> BoardCell { BoardCell(value: nil, status: "unavailable", note: why) }
}

nonisolated struct BoardMetrics: Equatable {
    var entryBoard = BoardCell.na("not computed")
    var entryAngleDeg = BoardCell.na("not computed")
    var arrowsBoard = BoardCell.na("not computed")      // board at 15 ft (the arrows)
    var laydownBoard = BoardCell.na("not computed")     // board at 0 ft (laydown)
    var boardAt7ft = BoardCell.na("not computed")
    var breakpointBoard = BoardCell.na("not computed")
    var breakpointDistanceFt = BoardCell.na("not computed")
    var launchAngleDeg = BoardCell.na("not computed")
    var rightHanded: Bool? = nil
    /// The LOESS board-vs-distance curve as ABSOLUTE (board 1 = right gutter) [z_ft, board] pairs — the ball path
    /// the shot card's lane view draws. Empty when the lateral path couldn't be fit.
    var curveZBoard: [[Double]] = []
    /// Raw per-point [z_ft, board] samples (absolute), for the measured-extent + dots on the lane view.
    var seriesZBoard: [[Double]] = []

    /// Flatten to the metric keys the server catalog / result card use. Unavailable cells are included (value
    /// nil) so the honesty layer + outcome rows see them.
    func metricPairs() -> [(String, BoardCell)] {
        [("entry_board", entryBoard), ("entry_angle", entryAngleDeg), ("arrows_board", arrowsBoard),
         ("laydown_board", laydownBoard), ("board_at_7ft", boardAt7ft),
         ("breakpoint_board", breakpointBoard), ("breakpoint_distance", breakpointDistanceFt),
         ("launch_angle", launchAngleDeg)]
    }
}

enum OnDeviceBoards {

    /// Compute the board metrics from the ball track + lane geometry + the speed fit (for t_impact / the foul
    /// crossing). `na` with a reason when the geometry/track can't support them — never a guessed board.
    nonisolated static func compute(track: BallTrack, geo: ODLaneGeometry, speed sp: SpeedEstimate) -> BoardMetrics {
        var out = BoardMetrics()
        func allNA(_ why: String) -> BoardMetrics {
            out.entryBoard = .na(why); out.entryAngleDeg = .na(why); out.arrowsBoard = .na(why)
            out.laydownBoard = .na(why); out.boardAt7ft = .na(why); out.breakpointBoard = .na(why)
            out.breakpointDistanceFt = .na(why); out.launchAngleDeg = .na(why); return out
        }
        let pts = track.points.sorted { $0.t < $1.t }
        guard pts.count >= 6, let foulY = geo.foulLineY, let vp = geo.vanishingPoint,
              let lane = track.selectedLane ?? geo.lanes.first,
              let tImpact = sp.tImpact else {
            return allNA("need \u{2265}6 track points + lane geometry + an impact anchor to read boards")
        }
        let vpY = Double(vp.y)

        // --- u(t) fit (u = 1/(contactRow - vpY), projectively linear in lane distance) → the impact anchor row.
        // Same fit speed() uses; recomputed here so boards stay self-contained.
        func u(_ ct: Double) -> Double { 1.0 / max(ct - vpY, 1.0) }
        var n = 0.0, st = 0.0, su = 0.0, stt = 0.0, stu = 0.0
        for p in pts { let tt = p.t, uu = u(Double(p.contactRow)); n += 1; st += tt; su += uu; stt += tt*tt; stu += tt*uu }
        let den = n*stt - st*st
        guard abs(den) > 1e-12 else { return allNA("degenerate trajectory fit") }
        let uSlope = (n*stu - st*su)/den, uIntc = (su - uSlope*st)/n
        let uImpact = uSlope*tImpact + uIntc
        guard uImpact > 1e-6 else { return allNA("impact anchor behind the camera horizon") }
        let impactRow = vpY + 1.0/uImpact

        // --- lane-plane homography from the lane quad. Foul line (Z=0) and the far cross-line at impact
        // (Z=Z_IMPACT) are taken HORIZONTAL (the on-device geometry gives a foul ROW, not a slanted line) — a
        // square rear view keeps both near-horizontal, so this matches the server's VP-derived lines closely.
        func laneX(_ y: Double) -> (Double, Double) {
            (Double(lane.left.a)*y + Double(lane.left.b), Double(lane.right.a)*y + Double(lane.right.b))
        }
        // Anchor Z=0 at the SELECTED lane's own near row (not the global geo.foulLineY, which is the right/first
        // lane's foul — using it for a ball on a different lane shifts the near-lane board scale). DEC-128.
        _ = foulY
        let fY = Double(lane.yNear)
        let (lf, rf) = laneX(fY), (li, ri) = laneX(impactRow)
        let img: [(Double, Double)] = [(lf, fY), (rf, fY), (ri, impactRow), (li, impactRow)]
        let world: [(Double, Double)] = [(0, 0), (B_LANE_IN, 0), (B_LANE_IN, B_Z_IMPACT), (0, B_Z_IMPACT)]
        guard let H = perspectiveTransform(img, world) else { return allNA("lane homography unsolvable") }

        // --- map the track into the lane plane; keep points physically on the lane before the pins.
        var tArr: [Double] = [], ZArr: [Double] = [], boardFromLeft: [Double] = []
        for p in pts {
            let (X, Z) = applyH(H, Double(p.cx), Double(p.contactRow))
            if !X.isFinite || !Z.isFinite || Z <= -3 || Z >= 61 { continue }
            tArr.append(p.t); ZArr.append(Z); boardFromLeft.append(X / B_LANE_IN * B_BOARDS + 0.5)
        }
        guard ZArr.count >= 6 else { return allNA("too few on-lane track points after rectification") }

        // --- handedness from the late hook direction (cubic board_from_left vs Z, slope at Z.max()).
        let zMax = ZArr.max()!, zMin = ZArr.min()!
        let pz = polyfit(ZArr, boardFromLeft, 3)
        let endSlope = polyval(polyder(pz), zMax)
        let rightHanded = endSlope < 0            // late move toward the LEFT edge = a right-hander's hook
        out.rightHanded = rightHanded
        // handed working frame + absolute-board reporter (1 = right gutter)
        let board = boardFromLeft.map { rightHanded ? (B_BOARDS + 1 - $0) : $0 }
        func toAbs(_ b: Double?) -> Double? { guard let b else { return nil }; return rightHanded ? b : (B_BOARDS + 1 - b) }

        // --- LOESS board-vs-distance, evaluated only where data exist (no gap extrapolation).
        var zz: [Double] = []
        var z = max(0.0, zMin)
        let zTop = min(B_Z_IMPACT, zMax + 1.0) + 1e-6
        while z <= zTop { if ZArr.contains(where: { abs($0 - z) < 3.0 }) { zz.append(z) }; z += 0.25 }
        guard zz.count >= 4 else { return allNA("lateral path too sparse to read boards") }
        let (bbRaw, slRaw) = loess(ZArr, board, zz, bw: 10.0, deg: 2, iters: 3)
        var zc: [Double] = [], bb: [Double] = [], sl: [Double] = []
        for i in 0..<zz.count where bbRaw[i].isFinite && slRaw[i].isFinite {
            zc.append(zz[i]); bb.append(bbRaw[i]); sl.append(slRaw[i])
        }
        guard zc.count >= 2 else { return allNA("lateral path fit failed") }
        // entry/launch angle: slope (boards/ft) → physical degrees
        let ang = sl.map { atan($0 * (B_LANE_IN / B_BOARDS) / 12.0) * 180.0 / .pi }
        let zcMin = zc.first!, zcMax = zc.last!

        // breakpoint = lateral extreme (min board in the handed frame) in the mid lane 15–55 ft
        let midIdx = (0..<zc.count).filter { zc[$0] > 15 && zc[$0] < 55 }
        if let k = midIdx.min(by: { bb[$0] < bb[$1] }) {
            out.breakpointBoard = .ok(toAbs(bb[k])!)
            // end of the flat (skid) top: first point after k that rises > 0.25 board
            if let after = (k..<zc.count).first(where: { bb[$0] > bb[k] + 0.25 }) {
                out.breakpointDistanceFt = .ok(zc[after])
            } else {
                out.breakpointDistanceFt = .na("breakpoint flat-top end not reached in the tracked span")
            }
        } else {
            out.breakpointBoard = .na("ball not tracked through the mid lane (15\u{2013}55 ft)")
            out.breakpointDistanceFt = .na("ball not tracked through the mid lane (15\u{2013}55 ft)")
        }

        // entry board/angle at impact (Z_IMPACT) — only if the track reaches near the pins (zz past 56 ft)
        let lateIdx = (0..<zc.count).filter { zc[$0] > zcMax - 1.5 }
        if !lateIdx.isEmpty {
            out.entryAngleDeg = .ok(lateIdx.map { ang[$0] }.reduce(0, +) / Double(lateIdx.count))
        }
        if zcMax > 56 {
            out.entryBoard = .ok(toAbs(interp(B_Z_IMPACT, zc, bb))!)
        } else {
            out.entryBoard = .na(String(format: "ball tracked to %.0f ft; entry board needs the track past 56 ft", zcMax))
        }

        // laydown (0 ft) / 7 ft / arrows (15 ft) — each only if the near lane was tracked that far up
        func boardAt(_ zq: Double, _ label: String) -> BoardCell {
            zcMin <= zq + 1 ? .ok(toAbs(interp(zq, zc, bb))!)
                            : .na(String(format: "near lane tracked from %.0f ft; %@ needs \u{2264} %.0f ft", zcMin, label, zq))
        }
        out.laydownBoard = boardAt(0, "laydown")
        out.boardAt7ft = boardAt(7, "board at 7 ft")
        out.arrowsBoard = boardAt(15, "arrows board")
        if zcMin < 3 {
            let li2 = (0..<zc.count).filter { zc[$0] >= 1 && zc[$0] <= 10 }
            if !li2.isEmpty { out.launchAngleDeg = .ok(-(li2.map { ang[$0] }.reduce(0, +) / Double(li2.count))) }
        } else {
            out.launchAngleDeg = .na("launch angle needs the ball tracked near the foul line (< 3 ft)")
        }
        // the ball path the shot-card lane view draws: the LOESS curve + the raw samples, both ABSOLUTE boards.
        out.curveZBoard = (0..<zc.count).compactMap { i in toAbs(bb[i]).map { [zc[i], $0] } }
        out.seriesZBoard = (0..<ZArr.count).compactMap { i in toAbs(board[i]).map { [ZArr[i], $0] } }
        return out
    }

    // MARK: - numerics

    /// cv2.getPerspectiveTransform: 3x3 H mapping the 4 src points → the 4 dst points (H[8] = 1). Solves the
    /// 8x8 linear system. Returns H as a flat [9] (row-major) or nil if singular.
    nonisolated static func perspectiveTransform(_ src: [(Double, Double)], _ dst: [(Double, Double)]) -> [Double]? {
        guard src.count == 4, dst.count == 4 else { return nil }
        var A = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var b = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let (x, y) = src[i], (u, v) = dst[i]
            A[2*i]   = [x, y, 1, 0, 0, 0, -x*u, -y*u]; b[2*i] = u
            A[2*i+1] = [0, 0, 0, x, y, 1, -x*v, -y*v]; b[2*i+1] = v
        }
        guard let h = solveLinear(A, b) else { return nil }
        return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0]
    }

    /// (X, Z) = H · [x, y, 1], de-homogenized.
    nonisolated static func applyH(_ H: [Double], _ x: Double, _ y: Double) -> (Double, Double) {
        let w = H[6]*x + H[7]*y + H[8]
        return ((H[0]*x + H[1]*y + H[2]) / w, (H[3]*x + H[4]*y + H[5]) / w)
    }

    /// Gaussian elimination with partial pivoting. A is n×n (mutated copy), returns x or nil if singular.
    nonisolated static func solveLinear(_ A0: [[Double]], _ b0: [Double]) -> [Double]? {
        var A = A0, b = b0
        let n = b.count
        for col in 0..<n {
            var piv = col
            for r in (col+1)..<n where abs(A[r][col]) > abs(A[piv][col]) { piv = r }
            if abs(A[piv][col]) < 1e-12 { return nil }
            if piv != col { A.swapAt(piv, col); b.swapAt(piv, col) }
            let d = A[col][col]
            for r in 0..<n where r != col {
                let f = A[r][col] / d
                if f == 0 { continue }
                for c in col..<n { A[r][c] -= f * A[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in 0..<n { x[i] = b[i] / A[i][i] }
        return x
    }

    /// Least-squares polynomial fit of degree `deg` (coeffs HIGH→LOW, like numpy.polyfit) via normal equations.
    nonisolated static func polyfit(_ x: [Double], _ y: [Double], _ deg: Int) -> [Double] {
        let m = deg + 1
        // normal equations (Vandermonde^T V) c = V^T y, with columns x^deg … x^0 (to match polyval order)
        var ATA = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        var ATy = [Double](repeating: 0, count: m)
        for k in 0..<x.count {
            var vand = [Double](repeating: 0, count: m)   // vand[0]=x^deg … vand[m-1]=x^0 (HIGH→LOW, matches polyval)
            var pw = 1.0
            for j in 0..<m { vand[m-1-j] = pw; pw *= x[k] }
            for i in 0..<m { ATy[i] += vand[i]*y[k]; for j in 0..<m { ATA[i][j] += vand[i]*vand[j] } }
        }
        return solveLinear(ATA, ATy) ?? [Double](repeating: 0, count: m)
    }

    nonisolated static func polyval(_ c: [Double], _ x: Double) -> Double {
        var r = 0.0; for coef in c { r = r*x + coef }; return r      // c HIGH→LOW (Horner)
    }
    nonisolated static func polyder(_ c: [Double]) -> [Double] {
        let n = c.count - 1
        if n <= 0 { return [0] }
        var d = [Double](repeating: 0, count: n)
        for i in 0..<n { d[i] = c[i] * Double(n - i) }     // derivative, HIGH→LOW
        return d
    }

    /// Linear interpolation of value at xq over sorted (xs, ys); clamps to the ends (numpy.interp).
    nonisolated static func interp(_ xq: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        if xq <= xs.first! { return ys.first! }
        if xq >= xs.last! { return ys.last! }
        var k = 1; while k < xs.count && xs[k] < xq { k += 1 }
        let a = (xq - xs[k-1]) / max(xs[k] - xs[k-1], 1e-12)
        return ys[k-1] + a * (ys[k] - ys[k-1])
    }

    /// Robust local polynomial regression (tricube kernel, bisquare robustness) — port of cv/smooth.loess.
    /// Returns (values, slopes) at each query point xq.
    nonisolated static func loess(_ x: [Double], _ y: [Double], _ xq: [Double],
                                  bw: Double, deg: Int, iters: Int) -> ([Double], [Double]) {
        var rw = [Double](repeating: 1, count: x.count)
        // fit a local polynomial at q with weights w; returns (value at q, slope at q)
        func fitAt(_ q: Double, _ wExtra: [Double]) -> (Double, Double) {
            let m = deg + 1
            var w = [Double](repeating: 0, count: x.count)
            var active = 0
            for k in 0..<x.count {
                let d = abs(x[k] - q) / bw
                let tri = d < 1 ? pow(1 - d*d*d, 3) : 0
                w[k] = tri * wExtra[k]
                if w[k] > 0 { active += 1 }
            }
            if active < deg + 2 { return (.nan, .nan) }
            // weighted LSQ on basis (x-q)^j, j=0..deg → c[0] = value at q, c[1] = slope at q
            var ATA = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var ATy = [Double](repeating: 0, count: m)
            for k in 0..<x.count where w[k] > 0 {
                var basis = [Double](repeating: 0, count: m)
                var p = 1.0; let dx = x[k] - q
                for j in 0..<m { basis[j] = p; p *= dx }
                for i in 0..<m { ATy[i] += w[k]*basis[i]*y[k]; for j in 0..<m { ATA[i][j] += w[k]*basis[i]*basis[j] } }
            }
            guard let c = solveLinear(ATA, ATy) else { return (.nan, .nan) }
            return (c[0], m > 1 ? c[1] : 0)
        }
        for _ in 0..<iters {
            var r = [Double](repeating: 0, count: x.count)
            for k in 0..<x.count { let f = fitAt(x[k], rw).0; r[k] = f.isFinite ? y[k] - f : 0 }
            let s = median(r.map { abs($0) }) * 6 + 1e-9
            for k in 0..<x.count { let u = max(-1, min(1, r[k]/s)); rw[k] = pow(1 - u*u, 2) }
        }
        var vals = [Double](repeating: 0, count: xq.count), slopes = [Double](repeating: 0, count: xq.count)
        for i in 0..<xq.count { let (v, sl) = fitAt(xq[i], rw); vals[i] = v; slopes[i] = sl }
        return (vals, slopes)
    }

    nonisolated static func median(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        let s = a.sorted(); let n = s.count
        return n % 2 == 1 ? s[n/2] : (s[n/2 - 1] + s[n/2]) / 2
    }
}
