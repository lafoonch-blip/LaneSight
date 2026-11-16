import XCTest
import CoreVideo
import simd
@testable import LaneSight

// DEC-117 Track A item 2 — Swift lane-detector parity vs ios_parity_golden. The Swift OnDeviceLaneDetector is a
// line-for-line port of lanesight_core/cv/lanes.py find_lanes; this test feeds it the SAME stabilized background
// plate the Python reference consumed and asserts the geometry matches the golden:
//   • vanishing point within 5 px
//   • foul-line corners within 2 px
//
// Two paths, so a divergence localises:
//   GEOMETRY path — runs detect(strictMask:looseMask:) on the Python-produced masks (isolates the tracks → fit →
//                   refine → foul → VP port from the HSV/morphology port). This is the hard gate.
//   PLATE path    — runs detect(pixelBuffer:) on the raw BGRA plate (also exercises the HSV mask + morphology).
//                   Reported; asserted within the same tolerance.
//
// Fixtures live in the test bundle under ParityFixtures/ (gitignored, added via project.yml). Absent → SKIP.
// Regenerate: scratchpad/parity_gen.py.
final class OnDeviceLaneParityTests: XCTestCase {
    struct Golden {
        let w: Int, h: Int
        let vp: SIMD2<Double>
        let foul: [SIMD2<Double>]
        let leftAB: SIMD2<Double>
        let rightAB: SIMD2<Double>
    }
    let clips = ["IMG_8751", "IMG_8752", "IMG_8753", "IMG_8754"]
    let VP_TOL = 5.0
    let FOUL_TOL = 2.0

    private func bundle() -> Bundle { Bundle(for: type(of: self)) }

    private func loadGolden(_ clip: String) -> Golden? {
        guard let url = bundle().url(forResource: "golden_\(clip)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let img = obj["image"] as? [String: Any], let lane = obj["lane"] as? [String: Any],
              let w = img["w"] as? Int, let h = img["h"] as? Int,
              let vp = lane["vp"] as? [Double], let fc = lane["foul_corners"] as? [[Double]],
              let lab = lane["left_ab"] as? [Double], let rab = lane["right_ab"] as? [Double] else { return nil }
        return Golden(w: w, h: h, vp: SIMD2(vp[0], vp[1]),
                      foul: fc.map { SIMD2($0[0], $0[1]) },
                      leftAB: SIMD2(lab[0], lab[1]), rightAB: SIMD2(rab[0], rab[1]))
    }

    private func loadBytes(_ name: String, _ ext: String) -> [UInt8]? {
        guard let url = bundle().url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else { return nil }
        return [UInt8](data)
    }

    /// Build a 32BGRA CVPixelBuffer from raw w*h*4 BGRA bytes (row-major, no padding in the source).
    private func pixelBuffer(_ bgra: [UInt8], w: Int, h: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let px = pb else { return nil }
        CVPixelBufferLockBaseAddress(px, [])
        defer { CVPixelBufferUnlockBaseAddress(px, []) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }
        let dstRB = CVPixelBufferGetBytesPerRow(px)
        let dst = base.assumingMemoryBound(to: UInt8.self)
        bgra.withUnsafeBufferPointer { src in
            for y in 0..<h {
                memcpy(dst + y * dstRB, src.baseAddress! + y * w * 4, w * 4)
            }
        }
        return px
    }

    private func dist(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { simd_distance(a, b) }

    private func report(_ clip: String, _ path: String, _ geo: ODLaneGeometry, _ g: Golden) -> (vpd: Double, foulMax: Double) {
        let d = geo.debug
        let vp = geo.vanishingPoint.map { SIMD2(Double($0.x), Double($0.y)) }
        let vpd = vp.map { dist($0, g.vp) } ?? .infinity
        var foulMax = Double.infinity
        if let fc = geo.foulCorners, fc.count == 2 {
            foulMax = max(dist(fc[0], g.foul[0]), dist(fc[1], g.foul[1]))
        }
        let vpStr = vp.map { "(\(String(format: "%.1f", $0.x)),\(String(format: "%.1f", $0.y)))" } ?? "nil"
        let foulStr = geo.foulCorners.map { fc in fc.map { "(\(String(format: "%.1f", $0.x)),\(String(format: "%.1f", $0.y)))" }.joined(separator: " ") } ?? "nil"
        print("PARITY \(clip) [\(path)] VP=\(vpStr) golden=(\(String(format: "%.1f", g.vp.x)),\(String(format: "%.1f", g.vp.y))) dVP=\(String(format: "%.2f", vpd)) | foul=\(foulStr) dFoul=\(String(format: "%.2f", foulMax)) | mask_px=\(d.maskPixels) loose_px=\(d.loosePixels) nTracks=\(d.nTracks) nLanes=\(d.nLanes) nGood=\(d.nGood) rawVP=(\(String(format: "%.0f", d.rawVPx)),\(String(format: "%.0f", d.rawVPy))) used_s=\(d.usedS)")
        return (vpd, foulMax)
    }

    func testLaneParityGeometryPath() throws {
        var ran = 0
        for clip in clips {
            guard let g = loadGolden(clip),
                  let strict = loadBytes("\(clip)_strict", "u8"),
                  let loose = loadBytes("\(clip)_loose", "u8") else {
                print("PARITY \(clip) MISSING_FIXTURES (geometry)"); continue
            }
            ran += 1
            XCTAssertEqual(strict.count, g.w * g.h, "\(clip) strict mask size")
            let geo = OnDeviceLaneDetector.detect(strictMask: strict, looseMask: loose, w: g.w, h: g.h)
            let (vpd, foulMax) = report(clip, "geometry", geo, g)
            XCTAssertLessThan(vpd, VP_TOL, "\(clip) VP must be within \(VP_TOL)px of golden")
            XCTAssertLessThan(foulMax, FOUL_TOL, "\(clip) foul corners must be within \(FOUL_TOL)px of golden")
        }
        if ran == 0 { throw XCTSkip("no ParityFixtures in the test bundle") }
    }

    func testLaneParityPlatePath() throws {
        var ran = 0
        for clip in clips {
            guard let g = loadGolden(clip), let bgra = loadBytes("\(clip)_plate", "bgra") else {
                print("PARITY \(clip) MISSING_FIXTURES (plate)"); continue
            }
            XCTAssertEqual(bgra.count, g.w * g.h * 4, "\(clip) plate size")
            guard let px = pixelBuffer(bgra, w: g.w, h: g.h) else { XCTFail("\(clip) pixel buffer"); continue }
            ran += 1
            let geo = OnDeviceLaneDetector.detect(pixelBuffer: px)
            let (vpd, foulMax) = report(clip, "plate", geo, g)
            XCTAssertLessThan(vpd, VP_TOL, "\(clip) [plate] VP within \(VP_TOL)px (also validates HSV+morphology)")
            XCTAssertLessThan(foulMax, FOUL_TOL, "\(clip) [plate] foul within \(FOUL_TOL)px")
        }
        if ran == 0 { throw XCTSkip("no ParityFixtures in the test bundle") }
    }
}
