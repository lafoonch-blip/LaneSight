import Foundation
import AVFoundation
import CoreVideo
import Accelerate

// DEC-117 Track A — on-device decode plumbing shared by the detector + tracker:
//  1. display ROTATION. AVAssetReaderTrackOutput yields frames in STORAGE orientation (no transform), so a clip
//     recorded landscape with a -90 rotation flag (IMG_8751/8754: stored 1920×1080, displayed portrait 1080×1920)
//     reaches the detector sideways → degenerate geometry. We apply the track's preferredTransform rotation to
//     every decoded buffer, matching the server (cv/decode.py `_apply_rotation`: rotation -90 → ROTATE_90_CW), so
//     detect/track run in the SAME portrait space the ios_parity_golden plate encodes. Portrait clips (rotation 0)
//     are a pass-through (no copy).
//  2. the stabilized-ish BACKGROUND PLATE. The lane detector is validated on the server's background plate
//     (temporal median, bowler/ball removed), NOT a raw frame. On a tripod/near-static clip (the validation set:
//     camera motion ≤2 px) a per-pixel median over evenly-sampled rotation-corrected frames reproduces that plate
//     without per-frame warp. Full-res BGRA so the HSV wood mask + geometry match the golden.

nonisolated enum ODRotation { case r0, r90cw, r180, r270cw }

enum OnDeviceDecode {

    /// Display rotation from the video track's preferredTransform, mapped to the server's clockwise convention.
    nonisolated static func displayRotation(_ track: AVAssetTrack) -> ODRotation {
        let t = track.preferredTransform
        // rotation angle of the stored->display transform, rounded to a right angle
        var deg = Int((atan2(t.b, t.a) * 180 / .pi).rounded())
        deg = ((deg % 360) + 360) % 360
        switch deg {
        case 90: return .r90cw       // portrait-from-landscape (ffprobe -90) → rotate 90° CW (validated vs golden)
        case 180: return .r180
        case 270: return .r270cw
        default: return .r0
        }
    }

    /// Rotate a 32BGRA pixel buffer to display orientation. Returns the same buffer for .r0 (no copy).
    nonisolated static func rotated(_ px: CVPixelBuffer, _ rot: ODRotation) -> CVPixelBuffer? {
        if rot == .r0 { return px }
        let rotConst: UInt8
        switch rot {
        case .r90cw: rotConst = UInt8(kRotate90DegreesClockwise)
        case .r180: rotConst = UInt8(kRotate180DegreesClockwise)
        case .r270cw: rotConst = UInt8(kRotate270DegreesClockwise)
        case .r0: return px
        }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        guard let sbase = CVPixelBufferGetBaseAddress(px) else { return nil }
        let swap = (rot == .r90cw || rot == .r270cw)
        let dw = swap ? h : w, dh = swap ? w : h
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferCreate(nil, dw, dh, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out) == kCVReturnSuccess,
              let dst = out else { return nil }
        CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(dst, []) }
        guard let dbase = CVPixelBufferGetBaseAddress(dst) else { return nil }
        var srcB = vImage_Buffer(data: sbase, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                 rowBytes: CVPixelBufferGetBytesPerRow(px))
        var dstB = vImage_Buffer(data: dbase, height: vImagePixelCount(dh), width: vImagePixelCount(dw),
                                 rowBytes: CVPixelBufferGetBytesPerRow(dst))
        var bg: Pixel_8888 = (0, 0, 0, 255)
        _ = vImageRotate90_ARGB8888(&srcB, &dstB, rotConst, &bg, vImage_Flags(kvImageNoFlags))
        return dst
    }

    /// Full-res rotation-corrected background plate = per-pixel median of up to `maxFrames` evenly reservoir-
    /// sampled frames (bowler/ball removed), as a 32BGRA CVPixelBuffer. nil if the clip can't be read.
    nonisolated static func backgroundPlate(url: URL, maxFrames: Int = 15) -> (plate: CVPixelBuffer, rot: ODRotation)? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let rot = displayRotation(track)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        out.alwaysCopiesSampleData = false
        reader.add(out); reader.startReading()

        var samples: [[UInt8]] = []      // each: tightly-packed w*h*4 BGRA (rotation applied)
        var w = 0, h = 0, i = 0
        var rng: UInt64 = 0x2545F4914F6CDD1D
        func rnd(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(1, n))) }
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return nil }
            autoreleasepool {
                guard let raw = CMSampleBufferGetImageBuffer(sb), let rpx = rotated(raw, rot) else { return }
                CVPixelBufferLockBaseAddress(rpx, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(rpx, .readOnly) }
                let fw = CVPixelBufferGetWidth(rpx), fh = CVPixelBufferGetHeight(rpx)
                let rb = CVPixelBufferGetBytesPerRow(rpx)
                guard let base = CVPixelBufferGetBaseAddress(rpx)?.assumingMemoryBound(to: UInt8.self) else { return }
                if w == 0 { w = fw; h = fh }
                func packed() -> [UInt8] {
                    var p = [UInt8](repeating: 0, count: fw * fh * 4)
                    p.withUnsafeMutableBufferPointer { d in
                        for y in 0..<fh { memcpy(d.baseAddress! + y * fw * 4, base + y * rb, fw * 4) }
                    }
                    return p
                }
                if samples.count < maxFrames { samples.append(packed()) }
                else { let j = rnd(i + 1); if j < maxFrames { samples[j] = packed() } }
                i += 1
            }
        }
        guard !samples.isEmpty, w > 0, h > 0 else { return nil }
        // per-pixel, per-channel median
        var plateBytes = [UInt8](repeating: 0, count: w * h * 4)
        let n = samples.count
        var col = [UInt8](repeating: 0, count: n)
        plateBytes.withUnsafeMutableBufferPointer { outp in
            for p in stride(from: 0, to: w * h * 4, by: 4) {
                for c in 0..<3 {
                    for k in 0..<n { col[k] = samples[k][p + c] }
                    col.sort(); outp[p + c] = col[n / 2]
                }
                outp[p + 3] = 255
            }
        }
        // wrap into a CVPixelBuffer
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let plate = pb else { return nil }
        CVPixelBufferLockBaseAddress(plate, [])
        defer { CVPixelBufferUnlockBaseAddress(plate, []) }
        guard let dbase = CVPixelBufferGetBaseAddress(plate) else { return nil }
        let drb = CVPixelBufferGetBytesPerRow(plate)
        plateBytes.withUnsafeBufferPointer { src in
            let d = dbase.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h { memcpy(d + y * drb, src.baseAddress! + y * w * 4, w * 4) }
        }
        return (plate, rot)
    }
}
