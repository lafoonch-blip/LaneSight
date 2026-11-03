import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

/// On-device Form pose backend (DEC-128) — the faithful port of `lanesight_core/form/pose.py::extract_landmarks`.
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
enum FormPoseLandmarker {
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

    struct Landmarks {
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

    /// Default bundled model name (see project.yml; the .task is copied in, never committed — DEC-128/pose.py note).
    static let modelResource = "pose_landmarker_heavy"
    static let modelExtension = "task"

    /// Resolve the model path: an explicit override wins, else the app/test bundle resource.
    static func resolveModelPath(bundle: Bundle = .main, override: String? = nil) -> String? {
        if let override, FileManager.default.fileExists(atPath: override) { return override }
        if let env = ProcessInfo.processInfo.environment["LANESIGHT_POSE_MODEL"],
           FileManager.default.fileExists(atPath: env) { return env }
        return bundle.url(forResource: modelResource, withExtension: modelExtension)?.path
    }

    /// Run the heavy pose landmarker on every frame of `clipURL`. `modelPath` defaults to the bundled model.
    /// Honours `Task.isCancelled` (the 30 s primary cap / a superseded delivery) like the shot engines.
    static func extract(clipURL: URL, modelPath: String? = nil,
                        bundle: Bundle = .main) throws -> Landmarks {
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
            guard let px = OnDeviceDecode.rotated(raw, rot) else { continue }
            let tsMs = Int((t * 1000.0).rounded())
            var row = nanRow
            if let image = try? MPImage(pixelBuffer: px),
               let res = try? landmarker.detect(videoFrame: image, timestampInMilliseconds: max(0, tsMs)),
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
