import SwiftUI

/// Key position · full frame (v3.7 Figma 472:4185). Opened by tapping a key-position tile on the form card.
/// Shows the real exported frame for the position, the metrics measured AT that position ("At this
/// position"), and prev/next navigation between the available positions.
///
/// The design also overlays the pose skeleton + a "Skeleton" toggle. That overlay needs per-frame pose
/// keypoints, which the form pipeline doesn't yet persist on the record — so it's intentionally omitted
/// here (no fabricated skeleton). Once `after_form_analyzed` exports key-frame keypoints, this view draws
/// them (see the `keypoints` hook below) and the toggle appears; until then the honest frame stands alone.
struct KeyPositionFullView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let result: ShotResult
    @State private var index: Int
    @State private var image: UIImage?
    @State private var loading = false

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
                Text("The frame is from your clip. The pose skeleton overlay is coming — form keypoints aren’t exported yet, so it isn’t shown rather than guessed.")
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
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if loading {
                ProgressView().tint(LS.action)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "figure.bowling").font(.system(size: 34)).foregroundStyle(LS.borderStrong)
                    Text("Frame not available").font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
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
