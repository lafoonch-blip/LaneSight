import Foundation
import AVFoundation
import CoreMedia

/// DEC-133 recording-quality picker: the user-chosen recording format (resolution + fps), the device's supported
/// options, and persistence. Default **1080p120 SDR**; **Form floors at 60**. Only formats the back camera
/// actually offers are shown (hide 4K / 240 when unavailable). Capture is always SDR (CameraController pins HDR off).
struct CaptureChoice: Equatable, Sendable {
    var height: Int        // 1080 (Full HD) or 2160 (4K)
    var fps: Int           // 60 / 120 / 240

    var resLabel: String { height >= 2160 ? "4K" : "\(height)p" }
    var label: String { "\(resLabel) · \(fps) fps" }          // "1080p · 120 fps"
    var shortLabel: String { "\(resLabel) · \(fps)" }         // "1080p · 120" (rows/chips)

    /// Plain-language trade-off line shown under each option (design 822:4216).
    var tradeoff: String {
        switch (height, fps) {
        case (1080, 60):  return "Smallest files · least battery. Loft/entry need 60+."
        case (1080, 120): return "More detail for rev rate · recommended balance."
        case (1080, 240): return "Best rev-rate detail · larger files · more battery/heat."
        case (2160, 60):  return "Sharpest image · no measured accuracy gain · much larger files."
        case (2160, 120): return "4K detail at 120 · largest files · most battery/heat."
        default:          return "Larger files · more battery/heat at higher fps."
        }
    }
}

enum CaptureFormats {
    static let fallbackDefault = CaptureChoice(height: 1080, fps: 120)   // DEC-133: ships 1080p120 until gates pass
    static let formFloorFPS = 60

    // The design's candidate tiers. Shot offers 4K; Form is 1080 only (822:4216).
    static let shotTiers: [CaptureChoice] = [
        CaptureChoice(height: 1080, fps: 60), CaptureChoice(height: 1080, fps: 120),
        CaptureChoice(height: 1080, fps: 240),
        CaptureChoice(height: 2160, fps: 60), CaptureChoice(height: 2160, fps: 120),
    ]
    static let formTiers: [CaptureChoice] = [
        CaptureChoice(height: 1080, fps: 60), CaptureChoice(height: 1080, fps: 120),
        CaptureChoice(height: 1080, fps: 240),
    ]

    /// The subset of `tiers` the back wide camera supports (≥ that resolution at ≥ that fps). Hides 4K/240 rows
    /// when the phone can't do them (design: "only list formats the device actually supports").
    static func supported(_ tiers: [CaptureChoice]) -> [CaptureChoice] {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return tiers }
        let formats = dev.formats
        return tiers.filter { c in
            formats.contains { f in
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                let maxR = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return Int(d.height) >= c.height && maxR + 0.5 >= Double(c.fps)
            }
        }
    }

    // MARK: persistence — a Shot choice (resolution + fps) and a Form choice (1080p, fps only; floor 60)
    private static let kHeight = "ls.capture.height", kFPS = "ls.capture.fps", kFormFPS = "ls.capture.form_fps"

    static func savedShot() -> CaptureChoice {
        let d = UserDefaults.standard
        let h = d.object(forKey: kHeight) as? Int ?? fallbackDefault.height
        let f = d.object(forKey: kFPS) as? Int ?? fallbackDefault.fps
        return CaptureChoice(height: h, fps: f)
    }
    static func saveShot(_ c: CaptureChoice) {
        UserDefaults.standard.set(c.height, forKey: kHeight)
        UserDefaults.standard.set(c.fps, forKey: kFPS)
    }
    static func savedForm() -> CaptureChoice {
        let f = UserDefaults.standard.object(forKey: kFormFPS) as? Int ?? fallbackDefault.fps
        return CaptureChoice(height: 1080, fps: max(f, formFloorFPS))
    }
    static func saveForm(_ c: CaptureChoice) {
        UserDefaults.standard.set(max(c.fps, formFloorFPS), forKey: kFormFPS)
    }

    /// The format to actually capture for a mode. Form stays 1080p and never below 60 (DEC-121).
    static func effective(mode: String) -> CaptureChoice {
        mode == "form" ? savedForm() : savedShot()
    }
}
