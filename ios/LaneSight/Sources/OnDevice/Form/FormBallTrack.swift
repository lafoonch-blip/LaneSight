import Foundation

/// Ball-colour swing-track hook (DEC-128) — the analogue of `lanesight_core/form/pose.py::_ball_track`.
///
/// In the reference this tracks the ball as a dark, moderately-saturated round blob seeded near the bowling
/// wrist and uses it ONLY to confirm release (E7): accept the ball time only within +3 frames of the bottom of
/// the arc. On EVERY labeled form clip (validation/form_ondevice_golden.json) that confirmation did not move E7
/// past E6+dt — on the rear view the ball is occluded behind the body through the backswing, and on the side
/// view the bottom-of-arc wrist time already lands at release. So the on-device engine uses the wrist arc for
/// E7 (parity-exact there) and this tracker is OFF by default (`OnDeviceFormEngine.analyze(trackBall:)`).
///
/// It is left as an explicit hook — NOT silently dropped — so that if a future capture needs ball confirmation
/// it can be ported here (a faithful Swift port needs a deterministic per-pixel-median background plate, a
/// max-channel diff + HSV gate, morphological open/close, and seeded nearest-neighbour connected components;
/// OpenCV's exact CC/morphology are not bit-reproducible in Accelerate, so it would be validated against the
/// golden on device, like the lane parity fixtures).
enum FormBallTrack {
    /// Returns t -> (cx, cy, area) in normalized coords. Currently a no-op (see the type doc); the wrist arc is
    /// the release source on the labeled set. Kept so the engine's `trackBall:true` path has a real call site.
    static func track(clipURL: URL, t: [Double], frames: [FormPoseLandmarker.Frame],
                      t0: Double, t1: Double) -> [Double: (Double, Double, Int)] {
        return [:]
    }
}
