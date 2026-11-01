import Foundation
import simd

// DEC-117 item 3 — ball-INDEPENDENT metric lane-plane depth scale, ported from ops/metric_lane_plane.py (the
// Python reference, validated to recover synthetic Z exactly). Replaces the impact anchor for on-device speed:
// camera intrinsics K + lane-direction VP (lane edges) + a cross-lane VP (foul × a far cross-line: pin-deck or
// 15 ft arrows) + known width (41.5 in) → metric plane. Any image point → lane coords (Z ft down-lane).
//
// Intrinsics: on device, feed AVCameraCalibrationData's per-frame intrinsic matrix (DEC-117 item 2). The down-lane
// POV is focal-dominated (METRIC_LANE_PLANE_FINDINGS), so an accurate focal + a real second cross-line are
// required; a single foul line or an assumed focal is NOT reliable. The math here is proven by
// OnDeviceMetricPlaneTests (synthetic ground truth). Wiring it to a working on-device lane/ball track is pending.
nonisolated enum OnDeviceMetricPlane {
    static let laneIn: Double = 41.5

    struct Plane { let D: SIMD3<Double>; let C: SIMD3<Double>; let n: SIMD3<Double>; let c: Double
                   let origin: SIMD3<Double>; let K: simd_double3x3; let cosImg: Double }

    /// image line for x = a*y + b  ->  -x + a*y + b = 0  -> normalised [-1, a, b].
    static func lineFromAB(_ a: Double, _ b: Double) -> SIMD3<Double> {
        let l = SIMD3(-1, a, b); return l / simd_length(SIMD2(l.x, l.y))
    }
    static func lineThrough(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>) -> SIMD3<Double> {
        let l = simd_cross(SIMD3(p0.x, p0.y, 1), SIMD3(p1.x, p1.y, 1))
        return l / simd_length(SIMD2(l.x, l.y))
    }
    /// vpC = intersection of two parallel cross-lines (foul + a far line) — homogeneous (may be near-infinite).
    static func vpCTwoLines(_ foul: SIMD3<Double>, _ far: SIMD3<Double>) -> SIMD3<Double> { simd_cross(foul, far) }

    static func intrinsics(focalPx: Double, width: Double, height: Double) -> simd_double3x3 {
        simd_double3x3(rows: [SIMD3(focalPx, 0, width/2), SIMD3(0, focalPx, height/2), SIMD3(0, 0, 1)])
    }

    /// Solve the plane. vpL = lane-direction VP (edge intersection); vpCh = homogeneous cross VP. leftAB/rightAB =
    /// edge x=a·y+b; foulYL = foul row. Returns nil if degenerate.
    static func solve(K: simd_double3x3, vpL: SIMD2<Double>, vpCh: SIMD3<Double>,
                      leftAB: (Double, Double), rightAB: (Double, Double), foulYL: Double) -> Plane? {
        let Ki = K.inverse
        var D = Ki * SIMD3(vpL.x, vpL.y, 1); if D.z < 0 { D = -D }; D = simd_normalize(D)
        var C = Ki * vpCh; C = simd_normalize(C)
        let n = simd_normalize(simd_cross(D, C))
        func ray(_ px: Double, _ py: Double) -> SIMD3<Double> { let r = Ki * SIMD3(px, py, 1); return r.z < 0 ? -r : r }
        let xa = leftAB.0 * foulYL + leftAB.1, xb = rightAB.0 * foulYL + rightAB.1
        func onPlane(_ r: SIMD3<Double>, _ c: Double) -> SIMD3<Double> { (c / simd_dot(n, r)) * r }
        let wl = onPlane(ray(xa, foulYL), 1), wr = onPlane(ray(xb, foulYL), 1)
        let sep = abs(simd_dot(wr - wl, C))
        guard sep.isFinite, sep > 1e-9 else { return nil }
        let c = laneIn / sep
        let origin = onPlane(ray((xa + xb) / 2, foulYL), c)
        let cx = K[2, 0], cy = K[2, 1]      // simd columns: K[2] = (cx,cy,1) column
        var vpC2 = SIMD2(vpCh.x, vpCh.y); if abs(vpCh.z) > 1e-9 { vpC2 = vpC2 / vpCh.z } else { vpC2 = vpC2 * 1e6 }
        let dL = SIMD2(vpL.x - cx, vpL.y - cy), dC = vpC2 - SIMD2(cx, cy)
        let cosImg = simd_length(dC) > 0 ? abs(simd_dot(simd_normalize(dL), simd_normalize(dC))) : 1.0
        return Plane(D: D, C: C, n: n, c: c, origin: origin, K: K, cosImg: cosImg)
    }

    /// image point → down-lane distance Z (ft).
    static func zFt(_ p: Plane, _ px: Double, _ py: Double) -> Double {
        let Ki = p.K.inverse; var r = Ki * SIMD3(px, py, 1); if r.z < 0 { r = -r }
        let den = simd_dot(p.n, r); if abs(den) < 1e-9 { return .nan }
        return simd_dot((p.c / den) * r - p.origin, p.D) / 12.0
    }
}
