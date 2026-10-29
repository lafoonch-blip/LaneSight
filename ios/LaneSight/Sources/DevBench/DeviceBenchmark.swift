import SwiftUI
import AVFoundation
import Accelerate
import Vision
import PhotosUI
import UIKit

// OD-01 (DEC-102/103): device capability benchmark. Measures whether an iPhone can do the kind of per-frame
// work the CV pipeline needs, fast enough and without thermal/battery blowup — the gating evidence for moving
// measurement on-device (Phase 2+). No production CV here; this is an isolated, dev-panel-only harness.
//
// It reports, for a clip the owner picks from Photos:
//   • HEVC decode throughput (frames, decoded fps, realtime factor)
//   • a native per-frame processing step (vImage box convolve on the full frame) throughput
//   • peak memory (phys_footprint) during a sustained run
//   • a sustained ~30-pass run logging thermalState transitions, battery drain and per-pass time
// Compare these to the server baseline in ops/perf_reports/od00_server_baseline.json.

struct DeviceBenchmarkResult {
    var clipName = ""
    var frames = 0
    var width = 0
    var height = 0
    var nominalFPS = 0.0
    var clipSeconds = 0.0
    var decodeSeconds = 0.0            // one decode pass
    var processSeconds = 0.0           // one process pass (decode + native filter)
    var registrationSeconds = 0.0      // one pass: frame-to-frame Vision image registration (stabilization proxy)
    var registrationFrames = 0
    var passes = 0
    var sustainedSeconds = 0.0
    var perPassSeconds: [Double] = []
    var peakFootprintMB = 0.0
    var thermalTransitions: [String] = []
    var batteryStart: Float = -1
    var batteryEnd: Float = -1

    var decodedFPS: Double { decodeSeconds > 0 ? Double(frames) / decodeSeconds : 0 }
    var realtimeFactor: Double { decodeSeconds > 0 ? clipSeconds / decodeSeconds : 0 }   // >1 = faster than realtime
    var processedFPS: Double { processSeconds > 0 ? Double(frames) / processSeconds : 0 }
    var registrationFPS: Double { registrationSeconds > 0 ? Double(registrationFrames) / registrationSeconds : 0 }

    var report: String {
        func f(_ v: Double, _ n: Int = 1) -> String { String(format: "%.\(n)f", v) }
        var s = """
        LaneSight device benchmark (OD-01)
        Device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)
        Clip: \(clipName)  \(width)x\(height) @ \(f(nominalFPS))fps  \(f(clipSeconds))s  \(frames) frames

        DECODE (HEVC → BGRA)
          one pass: \(f(decodeSeconds, 2))s  →  \(f(decodedFPS))  decoded fps   (\(f(realtimeFactor))x realtime)
        NATIVE PROCESS (decode + vImage box-convolve, full frame)
          one pass: \(f(processSeconds, 2))s  →  \(f(processedFPS))  processed fps
        STABILIZATION PROXY (Vision frame-to-frame registration — the server's dominant CV cost)
          one pass: \(f(registrationSeconds, 2))s  →  \(f(registrationFPS))  registered fps  (\(registrationFrames) pairs)

        SUSTAINED RUN (\(passes) passes ≈ a \(passes)-shot session)
          total: \(f(sustainedSeconds))s   mean/pass: \(f(perPassSeconds.reduce(0,+) / Double(max(perPassSeconds.count,1)), 2))s
          peak memory (phys_footprint): \(f(peakFootprintMB)) MB
          battery: \(batteryStart < 0 ? "n/a" : "\(Int(batteryStart*100))% → \(Int(batteryEnd*100))%")
          thermal transitions: \(thermalTransitions.isEmpty ? "none (stayed \(ThermalWatch.describe(ProcessInfo.processInfo.thermalState)))" : thermalTransitions.joined(separator: " → "))
        """
        s += "\n\nInterpretation: compare one-pass process time to the server baseline (ops/perf_reports/od00_server_baseline.json)."
        return s
    }
}

enum ThermalWatch {
    nonisolated static func describe(_ s: ProcessInfo.ThermalState) -> String {
        switch s { case .nominal: return "nominal"; case .fair: return "fair"; case .serious: return "serious"
        case .critical: return "critical"; @unknown default: return "unknown" }
    }
}

/// phys_footprint in bytes (what iOS uses for the memory limit), via mach task_vm_info.
nonisolated func currentFootprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

actor DeviceBenchmarkRunner {
    /// Decode every frame of `url` once; optionally run the native filter on each. Returns (frames, w, h, seconds, peakBytes).
    private func decodePass(_ url: URL, process: Bool, trackPeak: Bool) throws -> (Int, Int, Int, Double, UInt64) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw BenchError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        out.alwaysCopiesSampleData = false
        reader.add(out)
        reader.startReading()

        var frames = 0, w = 0, h = 0
        var peak: UInt64 = 0
        var dst: vImage_Buffer? = nil
        var tempBuf: UnsafeMutableRawPointer? = nil
        defer { if let d = dst?.data { free(d) }; if let t = tempBuf { free(t) } }

        let t0 = CFAbsoluteTimeGetCurrent()
        while reader.status == .reading, let sb = out.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(px, .readOnly)
            w = CVPixelBufferGetWidth(px); h = CVPixelBufferGetHeight(px)
            if process, let base = CVPixelBufferGetBaseAddress(px) {
                let rowBytes = CVPixelBufferGetBytesPerRow(px)
                var src = vImage_Buffer(data: base, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                if dst == nil {
                    let d = malloc(rowBytes * h)
                    dst = vImage_Buffer(data: d, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                    // temp buffer for the convolve
                    let sz = vImageBoxConvolve_ARGB8888(&src, &dst!, nil, 0, 0, 5, 5, [0,0,0,0], vImage_Flags(kvImageGetTempBufferSize | kvImageEdgeExtend))
                    if sz > 0 { tempBuf = malloc(sz) }
                }
                // 5x5 box convolve on the full BGRA frame — a representative native per-frame filter.
                _ = vImageBoxConvolve_ARGB8888(&src, &dst!, tempBuf, 0, 0, 5, 5, [0,0,0,0], vImage_Flags(kvImageEdgeExtend))
            }
            CVPixelBufferUnlockBaseAddress(px, .readOnly)
            frames += 1
            if trackPeak { peak = max(peak, currentFootprintBytes()) }
        }
        let secs = CFAbsoluteTimeGetCurrent() - t0
        if reader.status == .failed { throw reader.error ?? BenchError.readFailed }
        return (frames, w, h, secs, peak)
    }

    /// Frame-to-frame Vision image registration (the primitive under stabilization — the server's dominant
    /// CV cost). Measures throughput on up to `maxPairs` consecutive full-res pairs. Hardware-accelerated.
    private func registrationPass(_ url: URL, maxPairs: Int) throws -> (Int, Double) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw BenchError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        out.alwaysCopiesSampleData = true    // we hold the previous frame across iterations
        reader.add(out); reader.startReading()
        let handler = VNSequenceRequestHandler()
        var prev: CVPixelBuffer?
        var pairs = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        while reader.status == .reading, pairs < maxPairs, let sb = out.copyNextSampleBuffer() {
            guard let cur = CMSampleBufferGetImageBuffer(sb) else { continue }
            if let p = prev {
                let req = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: cur)
                try? handler.perform([req], on: p)
                _ = req.results?.first as? VNImageTranslationAlignmentObservation
                pairs += 1
            }
            prev = cur
        }
        let secs = CFAbsoluteTimeGetCurrent() - t0
        if reader.status == .failed { throw reader.error ?? BenchError.readFailed }
        return (pairs, secs)
    }

    func run(url: URL, clipName: String, passes: Int, progress: @Sendable @escaping (String) -> Void) async throws -> DeviceBenchmarkResult {
        var r = DeviceBenchmarkResult()
        r.clipName = clipName
        r.passes = passes
        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            r.nominalFPS = Double(track.nominalFrameRate)
            r.clipSeconds = CMTimeGetSeconds(asset.duration)
        }

        progress("Decode pass…")
        let (f, w, h, decS, _) = try decodePass(url, process: false, trackPeak: false)
        r.frames = f; r.width = w; r.height = h; r.decodeSeconds = decS

        progress("Process pass…")
        let (_, _, _, procS, _) = try decodePass(url, process: true, trackPeak: false)
        r.processSeconds = procS

        progress("Stabilization (registration) pass…")
        let (regPairs, regS) = try registrationPass(url, maxPairs: 240)   // ~2s @120fps — enough for a stable rate
        r.registrationFrames = regPairs; r.registrationSeconds = regS

        // Sustained run with thermal/battery/memory tracking.
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }
        r.batteryStart = await MainActor.run { UIDevice.current.batteryLevel }
        var lastThermal = ProcessInfo.processInfo.thermalState
        r.thermalTransitions = []
        var peak: UInt64 = 0
        let sustStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<passes {
            let p0 = CFAbsoluteTimeGetCurrent()
            let (_, _, _, _, pk) = try decodePass(url, process: true, trackPeak: true)
            peak = max(peak, pk)
            r.perPassSeconds.append(CFAbsoluteTimeGetCurrent() - p0)
            let th = ProcessInfo.processInfo.thermalState
            if th != lastThermal {
                r.thermalTransitions.append("pass \(i): \(ThermalWatch.describe(lastThermal))→\(ThermalWatch.describe(th))")
                lastThermal = th
            }
            progress("Sustained \(i+1)/\(passes)  (\(ThermalWatch.describe(th)))")
        }
        r.sustainedSeconds = CFAbsoluteTimeGetCurrent() - sustStart
        r.peakFootprintMB = Double(peak) / 1_048_576.0
        r.batteryEnd = await MainActor.run { UIDevice.current.batteryLevel }
        return r
    }

    enum BenchError: Error { case noVideoTrack, readFailed }
}

struct DeviceBenchmarkView: View {
    @State private var picked: PhotosPickerItem?
    @State private var clipURL: URL?
    @State private var clipName = ""
    @State private var running = false
    @State private var status = ""
    @State private var result: DeviceBenchmarkResult?
    @State private var error: String?
    @State private var passes = 30
    private let runner = DeviceBenchmarkRunner()

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label(clipName.isEmpty ? "Pick a clip from Photos" : clipName, systemImage: "video")
                }
                Stepper("Sustained passes: \(passes)", value: $passes, in: 5...60, step: 5)
                Button {
                    Task { await run() }
                } label: {
                    HStack { Text("Run benchmark"); if running { Spacer(); ProgressView() } }
                }.disabled(running || clipURL == nil)
                if running, !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
            } header: { Text("OD-01 device benchmark") } footer: {
                Text("Pick one of your real bowling clips. Measures decode + native per-frame processing throughput, peak memory, and thermal/battery over a sustained run. Copy the report into 02_RESEARCH/DEVICE_BENCHMARK_<date>.md.")
            }
            if let result {
                Section("Report") {
                    Text(result.report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Device benchmark")
        .onChange(of: picked) { _, item in Task { await load(item) } }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("odbench_\(UUID().uuidString).mov")
            try data.write(to: tmp)
            clipURL = tmp
            clipName = "clip (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        } catch { self.error = "load failed: \(error.localizedDescription)" }
    }

    private func run() async {
        guard let url = clipURL else { return }
        running = true; error = nil; result = nil
        do {
            let r = try await runner.run(url: url, clipName: clipName, passes: passes) { s in
                Task { @MainActor in status = s }
            }
            result = r
        } catch { self.error = "benchmark failed: \(error.localizedDescription)" }
        running = false; status = ""
    }
}
