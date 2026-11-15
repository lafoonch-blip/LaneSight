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
    /// DEC-131 experiment result: kept FALSE (iOS default GPU/Metal delegate). Running the CPU (XNNPACK) delegate
    /// to match the Python reference was measured (form_lm_gap.py over the LMDUMP): the on-device landmarks already
    /// match the Python reference to ~1 px on the 60 fps clips (8825/8980) on BOTH delegates — the device-gate
    /// residuals + delivery windows came out byte-identical, so there was no landmark gap to close, and CPU was
    /// ~1-5 % slower. Flip to true + rebuild only to re-run that A/B. (The remaining on-device segmentation misses —
    /// 8980's walk-back pick, 8847 widening to ~43 s — are the delivery PRESCAN, not the delegate or landmarks.)
    static let useCPUDelegate = false

    /// Resolve the model path: an explicit override wins, then the env var, then the given bundle, then the app
    /// (main) bundle — the model ships as an app resource (Models/), so a test hosted in the app finds it there.
    static func resolveModelPath(bundle: Bundle = .main, override: String? = nil) -> String? {
        if let override, FileManager.default.fileExists(atPath: override) { return override }
        if let env = ProcessInfo.processInfo.environment["LANESIGHT_POSE_MODEL"],
           FileManager.default.fileExists(atPath: env) { return env }
        if let p = bundle.url(forResource: modelResource, withExtension: modelExtension)?.path { return p }
        return Bundle.main.url(forResource: modelResource, withExtension: modelExtension)?.path
    }

    /// DEC-129/131 motion scan: a CHEAP strided luma-diff pass (no pose) over the whole clip, returning the
    /// above-threshold motion bursts sorted by duration × mean energy (desc) + the clip time span, or nil for a
    /// clip too short to window. NO gap-bridging — a brief mid-approach dip splits a burst, which the swing-aware
    /// selector then re-ranks; bridging would merge a pre-shot shuffle into the delivery (the IMG_8825 divergence).
    /// Deterministic (pure arithmetic over decoded luma).
    private static func motionBursts(clipURL: URL, stride: Int) -> (bursts: [(Double, Double)], t0: Double, t1: Double)? {
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
            guard i % Swift.max(1, stride) == 0, let px = CMSampleBufferGetImageBuffer(sb) else { continue }
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
        let sorted = energy.sorted()
        let lo = sorted[Int(0.10 * Double(n))], hi = sorted[Int(0.90 * Double(n))]
        let thr = lo + 0.35 * (hi - lo)
        var all: [(Double, Double, Double)] = []     // (t0, t1, score = duration × mean energy)
        var k = 0
        while k < n {
            if energy[k] > thr {
                var j = k, sum = 0.0
                while j < n && energy[j] > thr { sum += energy[j]; j += 1 }
                let t0 = times[k], t1 = times[Swift.min(j - 1, n - 1)]
                all.append((t0, t1, (t1 - t0 + 1e-3) * (sum / Double(Swift.max(1, j - k)))))
                k = j
            } else { k += 1 }
        }
        guard !all.isEmpty else { return nil }
        return (all.sorted { $0.2 > $1.2 }.map { ($0.0, $0.1) }, times[0], times[n - 1])
    }

    /// DEC-129 prescan: the single dominant-motion delivery window [start − lead, end + tail], or nil (short clip /
    /// the window already covers most of the clip → pose the whole thing). Kept for callers that want one window.
    static func prescanWindow(clipURL: URL, stride: Int = 3,
                              leadMargin: Double = 1.6, tailMargin: Double = 0.9) -> (Double, Double)? {
        guard let mb = motionBursts(clipURL: clipURL, stride: stride), let b = mb.bursts.first else { return nil }
        let w0 = Swift.max(mb.t0, b.0 - leadMargin)
        let w1 = Swift.min(mb.t1, b.1 + tailMargin)
        if (w1 - w0) > 0.75 * (mb.t1 - mb.t0) { return nil }   // windowing saves little + risks clipping the delivery
        return (w0, w1)
    }

    /// DEC-131 swing-aware prescan: the top-`top` candidate delivery bursts (highest duration × mean energy first),
    /// each as (t0, t1). The caller coarse-poses each candidate window, scores it with the frozen shoulder-
    /// normalized selector, and full-rate-poses only the winner — so a high-energy walk-back (IMG_8980) can't be
    /// mistaken for the delivery just because it moves more. nil for a clip too short to window (pose the whole thing).
    static func prescanBursts(clipURL: URL, stride: Int = 3, top: Int = 3) -> [(Double, Double)]? {
        guard let mb = motionBursts(clipURL: clipURL, stride: stride) else { return nil }
        return Array(mb.bursts.prefix(Swift.max(1, top)))
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
    /// `windows` (if set) poses frames inside ANY of several ranges (the swing-aware prescan's candidate set).
    /// `poseStride` poses only every Nth in-window frame and, when > 1, KEEPS only those posed frames so the
    /// coarse landmarks are contiguous (foot-speed + burst detection aren't broken by NaN gaps) — used to cheaply
    /// SCORE candidate windows before the full-rate pose on the winner (DEC-131).
    static func extract(clipURL: URL, modelPath: String? = nil,
                        bundle: Bundle = .main, window: (Double, Double)? = nil,
                        windows: [(Double, Double)]? = nil, poseStride: Int = 1) throws -> Landmarks {
        #if canImport(MediaPipeTasksVision)
        guard let model = resolveModelPath(bundle: bundle, override: modelPath) else {
            throw PoseError.modelMissing(modelPath ?? "\(modelResource).\(modelExtension) (not in bundle)")
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = model
        // DEC-131 experiment: run on the CPU delegate (TFLite XNNPACK) to MATCH the Python reference, which uses the
        // MediaPipe default CPU delegate. iOS otherwise defaults to the GPU (Metal) delegate, whose heavy-model
        // output differs enough from XNNPACK to shift the delivery segmentation on edge-on clips (8825/8826/8980).
        if Self.useCPUDelegate { options.baseOptions.delegate = .CPU }
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
        let stride = Swift.max(1, poseStride)
        var inWinCount = 0

        while reader.status == .reading, let sb = rdOut.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); break }
            guard let raw = CMSampleBufferGetImageBuffer(sb) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            let inWindow: Bool
            if let windows { inWindow = windows.contains { t >= $0.0 && t <= $0.1 } }
            else if let window { inWindow = (t >= window.0 && t <= window.1) }
            else { inWindow = true }
            let doPose = inWindow && (inWinCount % stride == 0)
            if inWindow { inWinCount += 1 }
            // Multi-window (`windows`) and/or coarse (stride > 1): keep ONLY the posed, in-window frames so the output
            // is contiguous (NaN gaps between windows / strided frames would read as motion and break burst
            // detection). A single `window` at full rate keeps every frame (NaN outside) — exactly as before, so the
            // whole-clip and single-window paths are unchanged.
            if (windows != nil || stride > 1) && !doPose { continue }
            var row = nanRow
            // Skip the (expensive) rotate + pose on frames outside the delivery window — they stay NaN, which the
            // engine treats as "not visible", exactly as if the bowler weren't detected there.
            if doPose, let px = OnDeviceDecode.rotated(raw, rot),
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
