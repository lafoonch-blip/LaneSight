import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

/// On-device Form pose backend (DEC-129) — the faithful port of `lanesight_core/form/pose.py::extract_landmarks`.
///
/// Runs **MediaPipe Pose Landmarker (heavy, VIDEO mode)** on every decoded frame — the SAME model family and the
/// SAME 33-point BlazePose topology the server reference uses, so the swing/foot geometry is comparable for the
/// DEC-121 parity gate. This is deliberately **not** Apple Vision (`VNDetectHumanBodyPoseRequest`): Vision has no
/// foot-index / heel landmarks, and the foot-plant "staircase" that the step count + approach timing depend on
/// needs them. The legacy Vision shadow (`OnDeviceFormShadow`) is superseded by this engine.
///
/// Output matches Python's `(t[N], lms[N,33,5])`: per frame a presentation timestamp (seconds, from the real
/// container PTS — authoritative over nominal fps, DEC-028/092) and 33 landmarks each `(x, y, z, visibility,
/// presence)` with x/y normalized 0..1 in DISPLAY orientation. A frame with no detection is all-NaN, exactly
/// like the reference.
nonisolated enum FormPoseLandmarker {
    /// BlazePose 33-point landmark indices (identical to `pose.py`).
    enum LM {
        static let nose = 0
        static let lShoulder = 11, rShoulder = 12
        static let lHip = 23, rHip = 24
        static let lWrist = 15, rWrist = 16
        static let lAnkle = 27, rAnkle = 28
        static let lHeel = 29, rHeel = 30
        static let lFoot = 31, rFoot = 32
        static let rFootPts = [28, 32, 30]       // ankle, foot_index, heel (R_FOOT_PTS)
        static let lFootPts = [27, 31, 29]        // (L_FOOT_PTS)
    }

    /// One frame's pose: timestamp + a [33][5] array (x, y, z, visibility, presence); NaN where not detected.
    struct Frame {
        let t: Double
        /// [33][5] = x, y, z, visibility, presence. NaN components where the landmark is missing.
        let lm: [[Float]]
    }

    nonisolated struct Landmarks {
        let t: [Double]
        let frames: [Frame]
        /// Clip fps derived from the median PTS delta (matches `1/median(diff(t))` in `pose.analyze`).
        var fps: Double {
            guard t.count > 1 else { return 30.0 }
            var d = [Double]()
            d.reserveCapacity(t.count - 1)
            for i in 1..<t.count { d.append(t[i] - t[i - 1]) }
            let m = FormSignal.median(d)
            return (m > 1e-9) ? 1.0 / m : 30.0
        }
    }

    enum PoseError: Error, CustomStringConvertible {
        case mediaPipeUnavailable
        case modelMissing(String)
        case decodeFailed(String)
        case noFrames(String)
        var description: String {
            switch self {
            case .mediaPipeUnavailable:
                return "MediaPipeTasksVision is not linked in this build (add the pod/SPM dependency)."
            case .modelMissing(let p): return "pose model not found: \(p)"
            case .decodeFailed(let p): return "could not decode \(p)"
            case .noFrames(let p): return "no frames decoded from \(p)"
            }
        }
    }

    /// Default bundled model name (see project.yml; the .task is copied in, never committed — DEC-129/pose.py note).
    static let modelResource = "pose_landmarker_heavy"
    static let modelExtension = "task"

    /// Resolve the model path: an explicit override wins, then the env var, then the given bundle, then the app
    /// (main) bundle — the model ships as an app resource (Models/), so a test hosted in the app finds it there.
    static func resolveModelPath(bundle: Bundle = .main, override: String? = nil) -> String? {
        if let override, FileManager.default.fileExists(atPath: override) { return override }
        if let env = ProcessInfo.processInfo.environment["LANESIGHT_POSE_MODEL"],
           FileManager.default.fileExists(atPath: env) { return env }
        if let p = bundle.url(forResource: modelResource, withExtension: modelExtension)?.path { return p }
        return Bundle.main.url(forResource: modelResource, withExtension: modelExtension)?.path
    }

    /// DEC-129 runtime/segmentation prescan: a CHEAP strided motion-energy scan (no pose) that finds the dominant
    /// delivery window — the longest sustained-motion span (the approach + swing), scored by duration × mean energy.
    /// Returns [start − leadMargin, end + tailMargin] so the setup-hold lead-in + the finish hold are included, or
    /// nil for a short clip (run pose on the whole thing). Picking the DOMINANT motion span also makes segmentation
    /// robust: a pre-shot shuffle / walk-off can't be mistaken for the delivery (the IMG_8825 divergence), with no
    /// per-clip tuning. Deterministic (pure arithmetic over decoded luma).
    static func prescanWindow(clipURL: URL, stride: Int = 3,
                              leadMargin: Double = 1.6, tailMargin: Double = 0.9) -> (Double, Double)? {
        let asset = AVURLAsset(url: clipURL)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let rdOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        guard reader.canAdd(rdOut) else { return nil }
        reader.add(rdOut); reader.startReading()

        var times: [Double] = []
        var energy: [Double] = []
        var prev: [Double]? = nil
        var i = 0
        while reader.status == .reading, let sb = rdOut.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); break }
            defer { i += 1 }
            guard i % max(1, stride) == 0, let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            guard let grid = coarseLuma(px) else { continue }
            if let p = prev, p.count == grid.count {
                var s = 0.0
                for k in 0..<grid.count { s += abs(grid[k] - p[k]) }
                times.append(t); energy.append(s / Double(grid.count))
            }
            prev = grid
        }
        reader.cancelReading()
        let n = energy.count
        guard n >= 8 else { return nil }
        let dur = times[n - 1] - times[0]
        if dur < 8.0 { return nil }     // short clips: pose the whole thing, no windowing needed
        // Pick the DOMINANT motion burst (the one with the highest duration × mean energy), bridging short dips
        // (≤0.5 s) so a brief mid-approach slowdown doesn't split it. Isolating the delivery burst from a pre-shot
        // shuffle / setup fidget is what lets findDelivery segment the hard clips (IMG_8825) correctly — the full
        // clip (or a first-to-last-motion window) re-includes that motion and mis-segments. Generous margins
        // (lead for the setup-hold, tail for the finish-hold) keep the approach + finish inside the window.
        let sorted = energy.sorted()
        let lo = sorted[Int(0.10 * Double(n))], hi = sorted[Int(0.90 * Double(n))]
        let thr = lo + 0.35 * (hi - lo)
        // Pick the single STRICTLY-contiguous run of above-threshold motion with the highest duration×mean energy
        // — NO gap-bridging (bridging merges a pre-shot shuffle into the delivery run and re-breaks IMG_8825's
        // isolation). This tight burst is what lets findDelivery segment the hard side clips correctly on device.
        var best: (Double, Double, Double)? = nil     // (startT, endT, score)
        var k = 0
        while k < n {
            if energy[k] > thr {
                var j = k, sum = 0.0
                while j < n && energy[j] > thr { sum += energy[j]; j += 1 }
                let t0 = times[k], t1 = times[Swift.min(j - 1, n - 1)]
                let score = (t1 - t0 + 1e-3) * (sum / Double(Swift.max(1, j - k)))
                if best == nil || score > best!.2 { best = (t0, t1, score) }
                k = j
            } else { k += 1 }
        }
        guard let b = best else { return nil }
        let w0 = Swift.max(times[0], b.0 - leadMargin)
        let w1 = Swift.min(times[n - 1], b.1 + tailMargin)
        // If the generous window already covers most of the clip, windowing saves little and risks clipping the
        // delivery — pose the whole thing instead (correctness over a marginal speedup).
        if (w1 - w0) > 0.75 * dur { return nil }
        return (w0, w1)
    }

    /// Coarse luma grid (32×24) sampled from a BGRA pixel buffer — cheap, rotation-agnostic (motion is motion).
    private static func coarseLuma(_ px: CVPixelBuffer, cols: Int = 32, rows: Int = 24) -> [Double]? {
        guard CVPixelBufferGetPixelFormatType(px) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        let bpr = CVPixelBufferGetBytesPerRow(px)
        let p = base.assumingMemoryBound(to: UInt8.self)
        var out = [Double](repeating: 0, count: cols * rows)
        for ry in 0..<rows {
            let y = min(h - 1, (ry * h) / rows)
            for cx in 0..<cols {
                let x = min(w - 1, (cx * w) / cols)
                let o = y * bpr + x * 4
                // BGRA → luma (Rec.601 on B,G,R)
                out[ry * cols + cx] = 0.114 * Double(p[o]) + 0.587 * Double(p[o + 1]) + 0.299 * Double(p[o + 2])
            }
        }
        return out
    }

    /// Run the heavy pose landmarker on `clipURL`. `modelPath` defaults to the bundled model. When `window` is
    /// set, pose is run ONLY on frames inside [t0, t1] (others become NaN rows) — the DEC-129 runtime fix: a cheap
    /// motion prescan finds the delivery window and we skip the expensive rotate+detect outside it. Decode still
    /// walks every frame (timestamps stay authoritative). Honours `Task.isCancelled` (the 30 s cap / superseded).
    static func extract(clipURL: URL, modelPath: String? = nil,
                        bundle: Bundle = .main, window: (Double, Double)? = nil) throws -> Landmarks {
        #if canImport(MediaPipeTasksVision)
        guard let model = resolveModelPath(bundle: bundle, override: modelPath) else {
            throw PoseError.modelMissing(modelPath ?? "\(modelResource).\(modelExtension) (not in bundle)")
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = model
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.3
        options.minPosePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3
        let landmarker = try PoseLandmarker(options: options)

        let asset = AVURLAsset(url: clipURL)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else {
            throw PoseError.decodeFailed(clipURL.lastPathComponent)
        }
        // Decode BGRA and rotate to DISPLAY orientation (matches cv2.CAP_PROP_ORIENTATION_AUTO in the reference),
        // reusing the shot decode's validated rotation so the normalized coords share the server's frame space.
        let rot = OnDeviceDecode.displayRotation(track)
        let rdOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        guard reader.canAdd(rdOut) else { throw PoseError.decodeFailed(clipURL.lastPathComponent) }
        reader.add(rdOut)
        reader.startReading()

        var frames: [Frame] = []
        var ts: [Double] = []
        let nanRow = [[Float]](repeating: [Float](repeating: Float.nan, count: 5), count: 33)

        while reader.status == .reading, let sb = rdOut.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); break }
            guard let raw = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            var row = nanRow
            let inWindow = window == nil || (t >= window!.0 && t <= window!.1)
            // Skip the (expensive) rotate + pose on frames outside the delivery window — they stay NaN, which the
            // engine treats as "not visible", exactly as if the bowler weren't detected there.
            if inWindow, let px = OnDeviceDecode.rotated(raw, rot),
               let image = try? MPImage(pixelBuffer: px),
               let res = try? landmarker.detect(videoFrame: image, timestampInMilliseconds: max(0, Int((t * 1000.0).rounded()))),
               let first = res.landmarks.first {
                for (k, p) in first.enumerated() where k < 33 {
                    row[k] = [p.x, p.y, p.z,
                              p.visibility?.floatValue ?? Float.nan,
                              p.presence?.floatValue ?? Float.nan]
                }
            }
            frames.append(Frame(t: t, lm: row))
            ts.append(t)
        }
        if reader.status == .failed { throw PoseError.decodeFailed(clipURL.lastPathComponent) }
        guard !frames.isEmpty else { throw PoseError.noFrames(clipURL.lastPathComponent) }
        return Landmarks(t: ts, frames: frames)
        #else
        throw PoseError.mediaPipeUnavailable
        #endif
    }
}
