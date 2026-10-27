import AVFoundation
import Combine

enum CameraError: LocalizedError {
    case notReady
    case recording(String)
    var errorDescription: String? {
        switch self {
        case .notReady: return "Camera is not ready."
        case .recording(let s): return "Recording error: \(s)"
        }
    }
}

/// AVFoundation capture wrapper. Fully MainActor-isolated for easy SwiftUI binding; the one
/// background callback (recording finished) is `nonisolated` and hops back to the main actor.
/// Guards every device access so it degrades gracefully on the Simulator (no camera -> `unavailable`).
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case needsPermission        // notDetermined — show the priming screen before the iOS prompt
        case denied                 // user declined / restricted — show the "camera is off" screen
        case unavailable(String)    // no camera hardware (e.g. Simulator)
        case ready
        case recording
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeFPS: Double = 0
    @Published private(set) var resolution: String = ""

    /// User-chosen capture frame rate (120 / 60 / 30). The camera clamps to the highest supported
    /// rate ≤ this value. Set from Settings before `start()`; defaults to 120.
    var preferredFPS: Double = 120

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var configured = false
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private var device: AVCaptureDevice?        // the active back camera, for torch + zoom

    @Published private(set) var torchOn = false
    @Published private(set) var zoomFactor: CGFloat = 1

    /// Toggles the torch (flash) while framing/recording. No-op if the device has no torch.
    func toggleTorch() {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        torchOn.toggle()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }

    /// Sets the optical/digital zoom factor, clamped to the device's supported range.
    func setZoom(_ z: CGFloat) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let clamped = max(1, min(z, min(device.activeFormat.videoMaxZoomFactor, 8)))
        device.videoZoomFactor = clamped
        zoomFactor = clamped
        device.unlockForConfiguration()
    }

    var isRunnable: Bool { if case .ready = state { return true }; if case .recording = state { return true }; return false }

    // MARK: setup

    func start(preferredFPS: Double = 120) async {
        self.preferredFPS = preferredFPS
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            state = .needsPermission      // show the priming screen; request only when the user taps Continue
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable("Camera access unavailable.")
        }
    }

    /// Called from the priming screen's "Continue": asks iOS for access, then configures or shows denied.
    func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        if granted { configure() } else { state = .denied }
    }

    private func configure() {
        guard !configured else {
            if !session.isRunning { session.startRunning() }
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            state = .unavailable("No camera on this device (expected on Simulator).")
            return
        }

        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.notReady }
            session.addInput(input)
            guard session.canAddOutput(movieOutput) else { throw CameraError.notReady }
            session.addOutput(movieOutput)

            let chosen = bestFormat(for: device, preferred: preferredFPS)
            session.sessionPreset = (chosen != nil) ? .inputPriority : .high
            session.commitConfiguration()

            if let chosen {
                try device.lockForConfiguration()
                device.activeFormat = chosen.format
                let dur = CMTime(value: 1, timescale: CMTimeScale(chosen.fps))
                device.activeVideoMinFrameDuration = dur
                device.activeVideoMaxFrameDuration = dur
                device.unlockForConfiguration()
                activeFPS = chosen.fps
                resolution = "\(chosen.width)x\(chosen.height)"
            } else {
                let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                resolution = "\(dims.width)x\(dims.height)"
                activeFPS = device.activeFormat.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0
            }

            self.device = device
            configured = true
            state = .ready
            session.startRunning()
        } catch {
            session.commitConfiguration()
            state = .unavailable("Camera setup failed: \(error.localizedDescription)")
        }
    }

    /// Picks a >=1080p (falling back to >=720p) format at the highest supported frame rate that is
    /// ≤ the user's `preferred` choice (never faster than they asked — higher fps = bigger files).
    /// Returns nil if none qualify (then we keep the device default).
    private func bestFormat(for device: AVCaptureDevice, preferred: Double) -> (format: AVCaptureDevice.Format, fps: Double, width: Int32, height: Int32)? {
        // Candidate rates no higher than the user's choice, highest first.
        let targets = [120.0, 60.0, 30.0].filter { $0 <= preferred + 0.5 }.sorted(by: >)
        var best: (format: AVCaptureDevice.Format, fps: Double, width: Int32, height: Int32)?
        for minHeight: Int32 in [1080, 720] {
            for format in device.formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dims.height >= minHeight else { continue }
                let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                for t in targets where maxRate + 0.5 >= t {
                    if best == nil || t > best!.fps {
                        best = (format, t, dims.width, dims.height)
                    }
                    break
                }
            }
            if best != nil { break }   // prefer the higher resolution tier
        }
        return best
    }

    // MARK: recording

    func startRecording() {
        guard configured, !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanesight-shot-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording
    }

    func stopRecording() async throws -> URL {
        guard movieOutput.isRecording else { throw CameraError.notReady }
        return try await withCheckedThrowingContinuation { cont in
            self.stopContinuation = cont
            self.movieOutput.stopRecording()
        }
    }

    func stopSession() {
        if session.isRunning { session.stopRunning() }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // AVFoundation sets `error` even on some benign stops; treat a readable, non-empty file as success.
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let errMsg = error.map { String(describing: $0) }
        Task { @MainActor in
            self.state = .ready
            guard let cont = self.stopContinuation else { return }
            self.stopContinuation = nil
            if size > 0 {
                cont.resume(returning: outputFileURL)
            } else {
                cont.resume(throwing: CameraError.recording(errMsg ?? "empty recording"))
            }
        }
    }
}
