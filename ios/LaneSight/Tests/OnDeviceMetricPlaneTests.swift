import XCTest
import simd
@testable import LaneSight

// Synthetic ground-truth validation of the Swift metric-plane solver (mirrors ops/metric_lane_plane.py's
// self-test). Projects a known lane plane with a known camera, then checks the solver recovers Z exactly.
// Fast + headless (no clip decode) — runs on the Simulator.
final class OnDeviceMetricPlaneTests: XCTestCase {
    typealias V3 = SIMD3<Double>
    typealias V2 = SIMD2<Double>

    func scene(f: Double, pitchDeg: Double, height: Double, shift: Double) -> (simd_double3x3, simd_double3x3, V3) {
        let K = OnDeviceMetricPlane.intrinsics(focalPx: f, width: 1080, height: 1920)
        let th = pitchDeg * .pi / 180
        let R = simd_double3x3(rows: [V3(1, 0, 0), V3(0, cos(th), -sin(th)), V3(0, sin(th), cos(th))])
        let t = -(R * V3(0, height, -shift))
        return (K, R, t)
    }
    func proj(_ K: simd_double3x3, _ R: simd_double3x3, _ t: V3, _ P: V3) -> V2 {
        let p = K * (R * P + t); return V2(p.x / p.z, p.y / p.z)
    }
    func edgeAB(_ K: simd_double3x3, _ R: simd_double3x3, _ t: V3, xIn: Double) -> (Double, Double) {
        var sy = 0.0, sx = 0.0, syy = 0.0, sxy = 0.0; let n = 60.0
        for i in 0..<60 {
            let z = 2000.0 * Double(i) / 59.0
            let p = proj(K, R, t, V3(xIn, 0, z)); sy += p.y; sx += p.x; syy += p.y*p.y; sxy += p.y*p.x
        }
        let a = (n*sxy - sy*sx) / (n*syy - sy*sy); let b = (sx - a*sy)/n; return (a, b)   // x = a·y + b
    }

    func testRecoversSyntheticZ() throws {
        let cases: [(Double, Double)] = [(1594, 12), (1594, 25), (1100, 18), (2400, 12)]
        let truth: [Double] = [5, 15, 30, 45, 59.44]
        for (f, pitch) in cases {
            let (K, R, t) = scene(f: f, pitchDeg: pitch, height: 42, shift: 70)
            let lab = edgeAB(K, R, t, xIn: -OnDeviceMetricPlane.laneIn/2)
            let rab = edgeAB(K, R, t, xIn:  OnDeviceMetricPlane.laneIn/2)
            let vpLh = simd_cross(OnDeviceMetricPlane.lineFromAB(lab.0, lab.1),
                                  OnDeviceMetricPlane.lineFromAB(rab.0, rab.1))
            let vpL = V2(vpLh.x/vpLh.z, vpLh.y/vpLh.z)
            let foul = OnDeviceMetricPlane.lineThrough(proj(K, R, t, V3(-200, 0, 0)), proj(K, R, t, V3(200, 0, 0)))
            let arrow = OnDeviceMetricPlane.lineThrough(proj(K, R, t, V3(-200, 0, 15*12)), proj(K, R, t, V3(200, 0, 15*12)))
            let foulYL = proj(K, R, t, V3(0, 0, 0)).y
            guard let plane = OnDeviceMetricPlane.solve(K: K, vpL: vpL, vpCh: OnDeviceMetricPlane.vpCTwoLines(foul, arrow),
                                                        leftAB: lab, rightAB: rab, foulYL: foulYL) else {
                return XCTFail("solve returned nil for f=\(f) pitch=\(pitch)")
            }
            var maxErr = 0.0
            for zT in truth {
                let pt = proj(K, R, t, V3(0, 0, zT*12)); let zR = OnDeviceMetricPlane.zFt(plane, pt.x, pt.y)
                maxErr = max(maxErr, abs(zR - zT))
            }
            print("METRIC_SELFTEST f=\(f) pitch=\(pitch) maxErr=\(String(format: "%.4f", maxErr))ft")
            XCTAssertLessThan(maxErr, 0.05, "f=\(f) pitch=\(pitch) Z recovery off by \(maxErr) ft")
        }
    }
}
