import AVFoundation
import CoreGraphics

/// Trims a recorded clip down to the shot window ON-DEVICE before upload, to keep uploads small
/// WITHOUT lowering frame rate or resolution.
///
/// Strategy (per the capture spec):
///  1. The start/stop tap boundaries are the primary window — that's the recorded clip itself.
///  2. A lightweight motion pre-pass samples frames (downscaled, ~20 Hz) and finds the active-motion
///     span inside that window, then pads ~0.4s on each side.
///  3. The trimmed segment is exported via AVAssetExportSession **passthrough** — original codec,
///     frame rate and resolution are preserved exactly (no re-encode, no downsample).
///  4. If the pre-pass isn't confident, or trimming would barely help, or export fails, the full
///     tap-window clip is used unchanged.
///
/// Everything runs off the main actor (the entry point is `nonisolated async`).
enum VideoTrimmer {
    nonisolated static func trimToShotWindow(_ sourceURL: URL, pad: Double = 0.4) async -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let duration = try? await asset.load(.duration) else { return sourceURL }
        let total = duration.seconds
        guard total.isFinite, total > 1.2 else { return sourceURL }   // too short to bother

        guard let range = await motionWindow(asset: asset, total: total, pad: pad) else {
            return sourceURL   // no confident motion → send the full tap-window clip
        }
        // Skip the export if trimming would barely shrink the clip.
        if range.duration.seconds > total * 0.85 { return sourceURL }

        return await export(asset: asset, range: range) ?? sourceURL
    }

    /// Returns the active-motion time range (padded) inside the clip, or nil if not confident.
    private nonisolated static func motionWindow(asset: AVURLAsset, total: Double, pad: Double) async -> CMTimeRange? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)    // downscale the ANALYSIS frames only
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

        let step = 0.05              // ~20 Hz sampling
        let gridW = 32, gridH = 18   // coarse luma signature per frame

        var times: [Double] = []
        var t = 0.0
        while t < total { times.append(t); t += step }
        guard times.count >= 4 else { return nil }

        var signatures: [[Float]] = []
        var sampleTimes: [Double] = []
        for ts in times {
            let cm = CMTime(seconds: ts, preferredTimescale: 600)
            guard let cg = try? await gen.image(at: cm).image else { continue }
            if let sig = signature(cg, width: gridW, height: gridH) {
                signatures.append(sig)
                sampleTimes.append(ts)
            }
        }
        guard signatures.count >= 4 else { return nil }

        // Frame-to-frame L1 difference of the coarse luma signature = motion energy.
        var motion = [Float](repeating: 0, count: signatures.count)
        for i in 1..<signatures.count {
            let a = signatures[i], b = signatures[i - 1]
            var acc: Float = 0
            for k in 0..<a.count { acc += abs(a[k] - b[k]) }
            motion[i] = acc / Float(a.count)
        }

        let peak = motion.max() ?? 0
        guard peak > 0 else { return nil }
        let threshold = max(peak * 0.18, 2.0)   // 18% of peak, with a tiny floor on the 0...255 scale

        var firstActive: Int?
        var lastActive: Int?
        for i in 0..<motion.count where motion[i] >= threshold {
            if firstActive == nil { firstActive = i }
            lastActive = i
        }
        guard let first = firstActive, let last = lastActive, last >= first else { return nil }

        let startT = max(0, sampleTimes[first] - pad)
        let endT = min(total, sampleTimes[last] + pad)
        guard endT > startT + 0.3 else { return nil }

        return CMTimeRange(start: CMTime(seconds: startT, preferredTimescale: 600),
                           end: CMTime(seconds: endT, preferredTimescale: 600))
    }

    /// Draws the frame into a tiny grayscale bitmap and returns its pixels as a luma signature.
    private nonisolated static func signature(_ image: CGImage, width w: Int, height h: Int) -> [Float]? {
        var buffer = [UInt8](repeating: 0, count: w * h)
        let gray = CGColorSpaceCreateDeviceGray()
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: gray,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return buffer.map(Float.init)
    }

    /// Passthrough-exports the given range to a new temp .mov (original fps + resolution preserved).
    private nonisolated static func export(asset: AVURLAsset, range: CMTimeRange) async -> URL? {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return nil
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanesight-trim-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: out)
        session.timeRange = range
        do {
            try await session.export(to: out, as: .mov)
            return out
        } catch {
            return nil
        }
    }
}
