import Foundation
import AVFoundation
import Vision
import simd

// DEC-102/103 — Phase 3, stage 1 (SHADOW). First real port of a CV stage to the device: stabilization.
// Mirrors the server's model (lanesight_core/cv/stabilize.py): register every frame to a REFERENCE frame and
// produce a per-frame homography (frame → reference). The server uses ORB + RANSAC homography at 0.5 scale;
// the device uses Vision's hardware-accelerated homographic registration — the closest native equivalent.
//
// Frames are STREAMED (AVAssetReader, one at a time) — OD-01 showed this keeps peak memory ~68 MB vs the
// server's ~2 GB. Output is the evidence stage-1 input for tracking; it is SHADOW — logged/compared, never
// shown or counted — until the DEC-103 ground-truth + parity gates pass.

/// One frame's registration to the reference frame.
struct FrameRegistration: Codable, Equatable {
    let frame: Int
    let ok: Bool
    /// 3x3 homography (row-major, frame → reference). Identity when `ok` is false.
    let warp: [Float]
    /// Translation magnitude in pixels implied by the warp (quick sanity/compare signal).
    let translationPx: Float
}

struct StabilizationResult: Equatable {
    let referenceFrame: Int
    let frameCount: Int
    let registered: Int            // frames with a usable warp
    let seconds: Double
    let regs: [FrameRegistration]

    var registeredFraction: Double { frameCount > 1 ? Double(registered) / Double(frameCount - 1) : 0 }
    var fps: Double { seconds > 0 ? Double(frameCount) / seconds : 0 }
    var meanTranslationPx: Double {
        let t = regs.filter { $0.ok }.map { Double($0.translationPx) }
        return t.isEmpty ? 0 : t.reduce(0, +) / Double(t.count)
    }
}

actor OnDeviceStabilizer {
    enum StabError: Error { case noVideoTrack, noReferenceFrame, readFailed }

    /// Register every frame of `url` to the first frame (the reference). `stride` registers every Nth frame
    /// (1 = every frame, matching the server). Streams frames — never holds more than two at once.
    func stabilize(url: URL, stride: Int = 1) throws -> StabilizationResult {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw StabError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        out.alwaysCopiesSampleData = true     // we retain the reference frame for the whole pass
        reader.add(out)
        reader.startReading()

        // Reference = first decoded frame (as in cv/stabilize.py).
        guard let firstSB = out.copyNextSampleBuffer(), let reference = CMSampleBufferGetImageBuffer(firstSB) else {
            throw StabError.noReferenceFrame
        }
        let handler = VNSequenceRequestHandler()
        var regs: [FrameRegistration] = [FrameRegistration(frame: 0, ok: true, warp: Self.identity, translationPx: 0)]
        var i = 0, registered = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            i += 1
            guard let cur = CMSampleBufferGetImageBuffer(sb) else { continue }
            if stride > 1 && i % stride != 0 { continue }
            let req = VNHomographicImageRegistrationRequest(targetedCVPixelBuffer: cur)
            do {
                try handler.perform([req], on: reference)
                if let obs = req.results?.first as? VNImageHomographicAlignmentObservation {
                    let H = obs.warpTransform
                    let tx = H.columns.2.x, ty = H.columns.2.y
                    regs.append(FrameRegistration(frame: i, ok: true, warp: Self.flatten(H),
                                                  translationPx: (tx * tx + ty * ty).squareRoot()))
                    registered += 1
                } else {
                    regs.append(FrameRegistration(frame: i, ok: false, warp: Self.identity, translationPx: 0))
                }
            } catch {
                regs.append(FrameRegistration(frame: i, ok: false, warp: Self.identity, translationPx: 0))
            }
        }
        let secs = CFAbsoluteTimeGetCurrent() - t0
        if reader.status == .failed { throw reader.error ?? StabError.readFailed }
        return StabilizationResult(referenceFrame: 0, frameCount: i + 1, registered: registered, seconds: secs, regs: regs)
    }

    static let identity: [Float] = [1,0,0, 0,1,0, 0,0,1]
    nonisolated static func flatten(_ m: simd_float3x3) -> [Float] {
        // row-major
        [m.columns.0.x, m.columns.1.x, m.columns.2.x,
         m.columns.0.y, m.columns.1.y, m.columns.2.y,
         m.columns.0.z, m.columns.1.z, m.columns.2.z]
    }
}
