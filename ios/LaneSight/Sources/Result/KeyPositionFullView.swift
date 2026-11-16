import SwiftUI

/// Key position · full frame (v3.7 Figma 472:4185). Opened by tapping a key-position tile on the form card.
/// Shows the real exported frame for the position, the metrics measured AT that position ("At this
/// position"), and prev/next navigation between the available positions.
///
/// When the record carries per-frame pose keypoints (`key_frame_poses`, visibility-gated by the form
/// pipeline), the pose skeleton is drawn over the still with a "Skeleton · on/off" toggle. Only confident
/// joints are drawn — blurred/hidden limbs are omitted, never guessed — and a still with no confident pose
/// simply shows the frame alone.
struct KeyPositionFullView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let result: ShotResult
    @State private var index: Int
    @State private var image: UIImage?
    @State private var loading = false
    @State private var skeletonOn = true

    private var joints: [[Double]?] { result.keyFramePoses[current.key] ?? [] }
    private var hasSkeleton: Bool { joints.contains { $0 != nil } }

    /// The four canonical positions, filtered to those actually exported for this delivery.
    private let positions: [(key: String, event: String, label: String)]

    init(result: ShotResult, startKey: String) {
        self.result = result
        let all: [(key: String, event: String, label: String)] = [
            ("ball_start", "E2", "Ball start"), ("end_pushaway", "E3", "End of pushaway"),
            ("top_of_swing", "E4", "Top of swing"), ("release", "E7", "Release"),
        ]
        let avail = all.filter { result.keyFrames.contains($0.key) }
        self.positions = avail.isEmpty ? all : avail
        _index = State(initialValue: max(0, (avail.isEmpty ? all : avail).firstIndex { $0.key == startKey } ?? 0))
    }

    private var current: (key: String, event: String, label: String) { positions[index] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let n = result.shotNumber {
                    Text("‹ Delivery \(n)").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.link)
                }
                Text(current.label).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                Text(contextLine).font(.system(size: 13)).foregroundStyle(LS.textSecondary)

                frameView
                Text(hasSkeleton
                     ? "The skeleton shows only joints the pose detected with confidence; blurred or hidden limbs are left out, not guessed."
                     : "The frame is from your clip. No confident pose was detected for this still, so no skeleton is drawn.")
                    .font(.system(size: 11)).foregroundStyle(LS.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                atThisPositionCard
                navFooter
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationTitle("Key position").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
        .task(id: current.key) { await loadFrame() }
    }

    private var contextLine: String {
        var parts: [String] = []
        if let t = result.events[current.event] { parts.append(String(format: "%.2f s", t)) }
        if let v = viewLabel { parts.append(v) }
        parts.append("frame from your clip")
        return parts.joined(separator: " · ")
    }
    private var viewLabel: String? {
        switch result.formView {
        case "down_lane": return "down-lane view (detected)"
        case "side": return "side view (detected)"
        case "rear": return "rear view (detected)"
        case .some(let s) where !s.isEmpty && s != "unknown": return "\(s) view"
        default: return nil
        }
    }

    @ViewBuilder private var frameView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(LS.raised)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .overlay {
                        if skeletonOn && hasSkeleton {
                            SkeletonOverlay(joints: joints, imageSize: image.size)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if loading {
                ProgressView().tint(LS.action)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "figure.bowling").font(.system(size: 34)).foregroundStyle(LS.borderStrong)
                    Text("Frame not available").font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            }
            // "Skeleton · on/off" toggle chip (top-left), shown only when there's a skeleton to toggle.
            if image != nil && hasSkeleton {
                VStack {
                    HStack {
                        Button { withAnimation(.easeInOut(duration: 0.15)) { skeletonOn.toggle() } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "figure.walk").font(.system(size: 11, weight: .semibold))
                                Text("Skeleton · \(skeletonOn ? "on" : "off")").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(skeletonOn ? LS.action : LS.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // "At this position": the measured positions + this position's timing checkpoint, each with an honest
    // status tag (MEASURED / VS BASELINE / {VIEW} VIEW gate).
    private var atThisPositionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("At this position").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                .padding(.bottom, 8)
            let rows = metricRows
            if rows.isEmpty {
                Text("No measured values at this position for this clip.")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 8) {
                        Text(r.label).font(.system(size: 14)).foregroundStyle(LS.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.value).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(r.value == "—" ? LS.textFaint : LS.textPrimary).fixedSize()
                        tag(r.tag, r.tagColor)
                    }
                    .frame(minHeight: 36)
                    if i != rows.count - 1 { Divider().overlay(LS.cardStroke) }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private struct Row { let label: String; let value: String; let tag: String; let tagColor: Color }

    private var metricRows: [Row] {
        var rows: [Row] = []
        // The measured body positions (spine tilt, balance arm, shoulders, …) — gated rows read "—" + the view they need.
        let order = ["spine_tilt", "balance_arm", "shoulder_tilt", "follow_through", "finish_hold"]
        for key in order {
            guard let p = result.measuredPositions[key] else { continue }
            let label = Self.labels[key] ?? MetricDisplay.humanize(key)
            let measured = (p.status == "ok" || p.status == "measured" || p.status == "calibrated_estimate")
            let bestEffort = (p.status == "best_effort")
            if measured || bestEffort {
                let v = p.display ?? p.value.map { fmt($0, p.unit) } ?? "—"
                rows.append(Row(label: label, value: v,
                                tag: bestEffort ? "BEST EFFORT" : "MEASURED",
                                tagColor: bestEffort ? LS.bestEffort : LS.success))
            } else if let need = p.view_required {
                rows.append(Row(label: label, value: "—", tag: "\(need.uppercased()) VIEW", tagColor: LS.textFaint))
            }
        }
        // This position's timing checkpoint (compared to the Profile baseline).
        if let cp = timingForPosition, cp.status == "ok", let off = cp.offset {
            let side = off > 0 ? "late" : (off < 0 ? "early" : "on time")
            let v = off == 0 ? "on time" : String(format: "%.2f s %@", abs(off), side)
            rows.append(Row(label: cp.label ?? "Timing", value: v, tag: "VS BASELINE", tagColor: LS.bestEffort))
        }
        return rows
    }

    private var timingForPosition: TimingCheckpoint? {
        let map = ["ball_start": "T2", "end_pushaway": "T1", "top_of_swing": "T3", "release": "T4"]
        guard let id = map[current.key] else { return nil }
        return result.timingCheckpoints[id]
    }

    private var navFooter: some View {
        HStack {
            if index > 0 {
                Button { withAnimation { index -= 1; image = nil } } label: {
                    Text("‹ \(positions[index - 1].label)").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.link)
                }
            }
            Spacer()
            if index < positions.count - 1 {
                Button { withAnimation { index += 1; image = nil } } label: {
                    Text("\(positions[index + 1].label) ›").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.link)
                }
            }
        }
        .padding(.top, 4)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        }.fixedSize()
    }

    private func loadFrame() async {
        guard result.keyFrames.contains(current.key) else { image = nil; return }
        loading = true; defer { loading = false }
        if let client = try? model.makeClient(),
           let data = try? await client.shotFrame(shotId: result.shotId, key: current.key) {
            image = UIImage(data: data)
        } else { image = nil }
    }

    private func fmt(_ v: Double, _ unit: String?) -> String {
        switch unit { case "deg": return "\(Int(v.rounded()))°"; case "s": return String(format: "%.2f s", v)
        default: return String(format: "%.1f", v) }
    }

    private static let labels: [String: String] = [
        "spine_tilt": "Spine tilt", "balance_arm": "Balance arm", "shoulder_tilt": "Shoulders",
        "follow_through": "Follow-through", "finish_hold": "Finish hold", "foul_line_distance": "Foul line",
    ]
}

/// Draws the MediaPipe pose skeleton over the key-frame still. Joints are [x,y] normalized to the cropped
/// image (or nil for joints the pose wasn't confident about); edges render only when both endpoints exist.
struct SkeletonOverlay: View {
    let joints: [[Double]?]
    let imageSize: CGSize

    // MediaPipe Pose body edges (shoulders, arms, torso, legs, feet). Face/hands omitted for a clean overlay.
    private static let edges: [(Int, Int)] = [
        (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),        // shoulders + arms
        (11, 23), (12, 24), (23, 24),                            // torso
        (23, 25), (25, 27), (24, 26), (26, 28),                  // legs
        (27, 29), (27, 31), (29, 31), (28, 30), (28, 32), (30, 32)  // feet
    ]

    var body: some View {
        GeometryReader { g in
            let rect = Self.fittedRect(imageSize, in: g.size)
            Canvas { ctx, _ in
                func pt(_ i: Int) -> CGPoint? {
                    guard i >= 0, i < joints.count, let j = joints[i], j.count == 2 else { return nil }
                    return CGPoint(x: rect.minX + CGFloat(j[0]) * rect.width,
                                   y: rect.minY + CGFloat(j[1]) * rect.height)
                }
                var line = Path()
                for (a, b) in Self.edges {
                    if let pa = pt(a), let pb = pt(b) { line.move(to: pa); line.addLine(to: pb) }
                }
                ctx.stroke(line, with: .color(LS.action), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                for i in joints.indices {
                    if let p = pt(i) {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white))
                    }
                }
            }
        }
    }

    /// The aspect-fit rect of `size` within `container` (matches Image.scaledToFit letterboxing).
    private static func fittedRect(_ size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}

#if DEBUG
extension SkeletonOverlay {
    /// A rough standing figure (normalized) for verifying the overlay renderer against a bundled photo.
    static let debugSample: [[Double]?] = {
        var j = [[Double]?](repeating: nil, count: 33)
        let set: [(Int, [Double])] = [
            (11, [0.42, 0.34]), (12, [0.58, 0.34]), (13, [0.37, 0.50]), (14, [0.63, 0.50]),
            (15, [0.34, 0.63]), (16, [0.66, 0.63]), (23, [0.45, 0.60]), (24, [0.55, 0.60]),
            (25, [0.44, 0.78]), (26, [0.56, 0.78]), (27, [0.43, 0.93]), (28, [0.57, 0.93]),
        ]
        for (i, p) in set { j[i] = p }
        return j
    }()
}
#endif
