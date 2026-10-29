import SwiftUI
import PhotosUI
import UIKit

// DEC-102/103 — Phase 3 shadow runner (dev-only). Runs the on-device stabilization stage on a picked clip and
// reports timing + registration quality so it can be compared to the server (parity gate). SHADOW: nothing
// here is shown to users or counted; it exists to validate the on-device engine against the reference.
struct OnDeviceShadowView: View {
    @State private var picked: PhotosPickerItem?
    @State private var clipURL: URL?
    @State private var clipName = ""
    @State private var running = false
    @State private var report = ""
    @State private var error: String?
    private let stabilizer = OnDeviceStabilizer()

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label(clipName.isEmpty ? "Pick a clip from Photos" : clipName, systemImage: "video")
                }
                Button {
                    Task { await run() }
                } label: {
                    HStack { Text("Run on-device stabilization"); if running { Spacer(); ProgressView() } }
                }.disabled(running || clipURL == nil)
                Button {
                    Task { await runLanes() }
                } label: {
                    HStack { Text("Run lane detection (stage 2)"); if running { Spacer(); ProgressView() } }
                }.disabled(running || clipURL == nil)
                Button {
                    Task { await runTrack() }
                } label: {
                    HStack { Text("Run ball tracking (stage 3)"); if running { Spacer(); ProgressView() } }
                }.disabled(running || clipURL == nil)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
            } header: { Text("On-device analysis — Stage 1 (shadow)") } footer: {
                Text("Ports the server's stabilization (frame→reference homography) to Vision on-device. Streams frames (memory-safe). Compare timing/quality to the server's cv.stabilize_s (~15s/clip).")
            }
            if !report.isEmpty {
                Section("Report") {
                    Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("On-device (shadow)")
        .onChange(of: picked) { _, item in Task { await load(item) } }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("odstab_\(UUID().uuidString).mov")
            try data.write(to: tmp)
            clipURL = tmp
            clipName = "clip (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        } catch { self.error = "load failed: \(error.localizedDescription)" }
    }

    private func run() async {
        guard let url = clipURL else { return }
        running = true; error = nil; report = ""
        do {
            let r = try await stabilizer.stabilize(url: url)
            func f(_ v: Double, _ n: Int = 1) -> String { String(format: "%.\(n)f", v) }
            report = """
            On-device stabilization (Stage 1, shadow)
            Device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)
            Frames: \(r.frameCount)   reference: frame \(r.referenceFrame)

            Registered: \(r.registered)/\(r.frameCount - 1)  (\(f(r.registeredFraction * 100))% of frames)
            Time: \(f(r.seconds, 2))s   →  \(f(r.fps)) fps
            Mean translation vs reference: \(f(r.meanTranslationPx)) px

            Server reference (OD-00): cv.stabilize_s ~15 s/clip.
            Read: registered% should be high (clean tripod → ~100%); low% flags a hard/handheld clip to review
            in the parity gate. Transforms are the stage-1 input for tracking (not yet ported).
            """
        } catch { self.error = "stabilize failed: \(error.localizedDescription)" }
        running = false
    }

    private func runLanes() async {
        guard let url = clipURL else { return }
        running = true; error = nil; report = ""
        // Detect on a steady early frame (stage-1 reference stand-in). Off the main actor (CV work).
        let geo: ODLaneGeometry? = await Task.detached {
            guard let px = OnDeviceLaneDetector.referenceFrame(url: url, at: 30) else { return nil }
            return OnDeviceLaneDetector.detect(pixelBuffer: px)
        }.value
        if let g = geo {
            func f(_ v: Float, _ n: Int = 1) -> String { String(format: "%.\(n)f", v) }
            let vp = g.vanishingPoint.map { "(\(f($0.x)), \(f($0.y)))" } ?? "— (unsolvable)"
            var lines = """
            On-device lane detection (Stage 2, first pass)
            Image: \(g.imageSize.x)x\(g.imageSize.y)   sat floor used: S>\(g.satFloorUsed)
            Lanes found (VP-agreeing): \(g.lanes.count)
            Vanishing point: \(vp)
            Foul line y: \(g.foulLineY.map(String.init) ?? "—")
            """
            for (i, l) in g.lanes.prefix(4).enumerated() {
                lines += "\n  lane \(i): left x=\(f(l.left.a,3))·y+\(f(l.left.b,1))  right x=\(f(l.right.a,3))·y+\(f(l.right.b,1))  nearWidth \(f(l.widthNearPx))px  y[\(l.yFar)…\(l.yNear)]"
            }
            lines += "\n\nFirst pass (port of cv/lanes.py). Eyeball: VP should sit above the lane, foul line near the\nbottom of the lane surface, nearWidth plausible. Mis-detections → threshold tuning (next)."
            report = lines
        } else { error = "lane detection: could not read a frame" }
        running = false
    }

    private func runTrack() async {
        guard let url = clipURL else { return }
        running = true; error = nil; report = ""
        let result: (ODLaneGeometry, BallTrack)? = await Task.detached {
            guard let px = OnDeviceLaneDetector.referenceFrame(url: url, at: 30) else { return nil }
            let geo = OnDeviceLaneDetector.detect(pixelBuffer: px)
            guard geo.vanishingPoint != nil, !geo.lanes.isEmpty else { return (geo, BallTrack(points: [], framesScanned: 0, candidateFrames: 0, seconds: 0)) }
            return (geo, OnDeviceTracker.track(url: url, geo: geo))
        }.value
        if let (geo, tr) = result {
            func f(_ v: Float, _ n: Int = 1) -> String { String(format: "%.\(n)f", v) }
            if geo.vanishingPoint == nil || geo.lanes.isEmpty {
                error = "tracking needs lane geometry — stage 2 found none on this clip"; running = false; return
            }
            var lines = """
            On-device ball tracking (Stage 3, first pass)
            Frames scanned: \(tr.framesScanned)   frames with a candidate: \(tr.candidateFrames)
            Track points (RANSAC inliers): \(tr.points.count)   time: \(f(Float(tr.seconds), 2))s
            """
            if let a = tr.points.first, let b = tr.points.last {
                lines += "\n  span: frac \(f(a.frac, 2)) → \(f(b.frac, 2))   t \(f(Float(a.t), 2))s → \(f(Float(b.t), 2))s"
            }
            // Stage 4 — first end-to-end metric: ball speed.
            let sp = OnDeviceTracker.speed(track: tr, foulLineY: geo.foulLineY)
            lines += "\n\n── Ball speed (stage 4, \(sp.basis)) ──"
            if let mph = sp.mph {
                lines += "\n  \(f(mph, 1)) mph   (release t=\(f(Float(sp.tRelease ?? 0), 2))s → impact t=\(f(Float(sp.tImpact ?? 0), 2))s)"
                if let ef = sp.entryFrac { lines += "\n  entry lateral fraction: \(f(ef, 2))  (0=left edge, 1=right edge)" }
            } else {
                lines += "\n  unavailable — \(sp.note)"
            }
            lines += "\n  \(sp.note)"
            lines += "\n\nFirst end-to-end metric on-device. Compare the mph to the server for the same clip (DEC-103 parity).\nIf it reads low/unavailable the track is short of the pins — next brick is pin-impact detection + the\n15 ft arrow anchor for a proper distance calibration. Eyeball the track too (diff/area/diameter are the levers)."
            report = lines
        } else { error = "tracking: could not read a frame" }
        running = false
    }
}
