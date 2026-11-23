import Foundation
import AVFoundation
import CoreMedia

/// DEC-133 "any video in": read the real capture properties off a clip (recorded OR imported) so metric
/// availability + precision follow the detected capture, never an estimate (DEC-026/027/028). Produces the
/// `capture_quality.capture` block the shot record carries. Pure AVFoundation, no UI.
enum CaptureProbe {

    enum DynamicRange: String { case sdr, hlg, pq, unknown }

    /// The detected capture, matching the `capture_quality.capture` record block. `fpsNominal` is the track's
    /// declared rate; `fpsMeasured` is derived from real presentation timestamps (catches variable frame rate and
    /// iPhone slo-mo, whose true capture rate is NOT the Photos slowed-playback rate).
    struct CaptureInfo {
        var width: Int
        var height: Int
        var fpsNominal: Double
        var fpsMeasured: Double
        var dynamicRange: DynamicRange
        var codec: String
        var durationS: Double
        var source: String            // "live" | "upload"

        var dict: [String: Any] {
            ["width": width, "height": height, "fps_nominal": round2(fpsNominal), "fps_measured": round2(fpsMeasured),
             "dynamic_range": dynamicRange.rawValue, "codec": codec, "duration_s": round2(durationS), "source": source]
        }
        private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    }

    /// Capture-floor gate (DEC-133 / DEC-026): the reason codes for metrics this capture can't support. Empty = OK.
    /// Mirrors failures.py (CAPTURE_FPS_BELOW_MIN / CAPTURE_RES_BELOW_MIN). The caller stamps the affected metrics
    /// `unavailable` with the specific reason — never estimated.
    static let minFPS = 30.0
    static let minHeight = 720
    static let formMinFPS = 60.0

    static func floorReasons(_ c: CaptureInfo, formMode: Bool) -> [(code: String, reason: String)] {
        var out: [(String, String)] = []
        let fps = max(c.fpsMeasured, c.fpsNominal)   // the real capture rate (slo-mo reads high here)
        let need = formMode ? formMinFPS : minFPS
        if fps + 0.5 < need {
            out.append(("CAPTURE_FPS_BELOW_MIN",
                        "recorded at \(Int(fps.rounded())) fps, need \(Int(need))+"))
        }
        if c.height < minHeight {
            out.append(("CAPTURE_RES_BELOW_MIN",
                        "recorded at \(c.height)p, need 720p+ with the lane and pins in frame"))
        }
        return out
    }

    /// DEC-133: tone-map an HDR (HLG/PQ, BT.2020) clip to SDR (BT.709) on device before analysis — a mismatched
    /// HDR tone-map broke ball tracking (DEC-113), so the engine only ever sees SDR frames. Returns a new SDR temp
    /// URL, or nil if the export failed (caller surfaces HDR_CONVERSION_FAILED). SDR input needs no conversion.
    static func convertToSDR(_ url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard asset.tracks(withMediaType: .video).first != nil else { return nil }
        let comp = AVMutableVideoComposition(propertiesOf: asset)
        comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("sdr-\(UUID().uuidString).mov")
        export.outputURL = out
        export.outputFileType = .mov
        export.videoComposition = comp
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        return export.status == .completed ? out : nil
    }

    /// One-call gate used at the on-device analysis entry: probe the clip, tone-map HDR→SDR if needed, and return
    /// the URL to analyze + the capture block + any capture-floor reasons. `analysisURL == nil` with an
    /// HDR_CONVERSION_FAILED reason means the HDR clip couldn't be converted.
    static func gate(url: URL, source: String, formMode: Bool) async
        -> (analysisURL: URL?, capture: CaptureInfo?, reasons: [(code: String, reason: String)]) {
        guard let info = probe(url: url, source: source) else { return (url, nil, []) }
        var reasons = floorReasons(info, formMode: formMode)
        var analysisURL: URL? = url
        if info.dynamicRange != .sdr {
            if let sdr = await convertToSDR(url) { analysisURL = sdr }
            else { analysisURL = nil; reasons.append(("HDR_CONVERSION_FAILED",
                "this clip is in an HDR format we couldn't convert to standard range on your device")) }
        }
        return (analysisURL, info, reasons)
    }

    /// Probe a clip. `source` is "live" (just recorded) or "upload" (imported).
    static func probe(url: URL, source: String) -> CaptureInfo? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        // display dimensions (apply the preferred transform so a portrait clip reports portrait)
        let natural = track.naturalSize.applying(track.preferredTransform)
        let width = Int(abs(natural.width).rounded()), height = Int(abs(natural.height).rounded())
        let fpsNominal = Double(track.nominalFrameRate)
        let durationS = CMTimeGetSeconds(asset.duration)

        var codec = "unknown"
        var range: DynamicRange = .sdr
        if let fd = (track.formatDescriptions as? [CMFormatDescription])?.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(fd))
            range = dynamicRange(fd)
        }
        let fpsMeasured = measureFPS(asset: asset, track: track) ?? fpsNominal
        return CaptureInfo(width: width, height: height, fpsNominal: fpsNominal, fpsMeasured: fpsMeasured,
                           dynamicRange: range, codec: codec, durationS: durationS, source: source)
    }

    // MARK: PTS-measured fps (real capture rate, incl. variable frame rate / slo-mo)

    private static func measureFPS(asset: AVAsset, track: AVAssetTrack, windowS: Double = 3.0) -> Double? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        out.alwaysCopiesSampleData = false
        guard reader.canAdd(out) else { return nil }
        reader.add(out); guard reader.startReading() else { return nil }
        var first: Double? = nil, last: Double = 0, n = 0
        while let sb = out.copyNextSampleBuffer() {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if t.isFinite {
                if first == nil { first = t }
                last = t; n += 1
                if let f = first, last - f >= windowS { break }
            }
        }
        reader.cancelReading()
        guard let f = first, n > 1, last > f else { return nil }
        return Double(n - 1) / (last - f)
    }

    // MARK: format description helpers

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let s = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? String(format: "0x%08x", code) : s
    }

    private static func dynamicRange(_ fd: CMFormatDescription) -> DynamicRange {
        guard let tf = CMFormatDescriptionGetExtension(fd, extensionKey: kCMFormatDescriptionExtension_TransferFunction) else {
            return .sdr
        }
        let s = tf as! CFString
        if CFEqual(s, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG) { return .hlg }
        if CFEqual(s, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ) { return .pq }
        return .sdr
    }
}
