import SwiftUI
import UIKit

/// The Form card (Form.dc.html, design 3.3/3.4): form fundamentals v1 (DEC-057). There is deliberately NO
/// entry board / breakpoint / score / "Apply this move" here — those are ball-only. Every value is live
/// from the form shot record (GET /shots/{id}) and the after_form_analyzed footer; a metric that couldn't
/// be measured shows "—" with its reason, an estimate carries a BEST EFFORT tag, and a swing baseline that
/// isn't set shows a "building" prompt. Nothing here is a fabricated number.
struct FormCardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: ShotResult

    /// Whether the pose backend itself couldn't run (top-level form status). When true the whole analysis
    /// is unavailable; otherwise the per-section honest states carry the story.
    private var topUnavailable: Bool { (result.formStatus ?? "").lowercased() == "unavailable" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextHeader
                    if topUnavailable {
                        unavailableCard
                    } else {
                        if result.formFocus != nil { focusCard }
                        keyPositionsSection
                        if !orderedCheckpoints.isEmpty { timingCheckpointsSection }
                        if result.swingTiming != nil { swingTimingSection }
                        if !approachMetrics.isEmpty { approachSection }
                        if !orderedPositions.isEmpty { positionsSection }
                        if let cues = result.coachingCues, let list = cues.cues, !list.isEmpty { coachingCuesSection(cues) }
                    }
                    footer
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { headerTitle }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss(); model.resetPipeline() }
                }
            }
        }
    }

    // MARK: context header

    /// Two-line nav title (v3.7): "Delivery N" (real sequence when present, else "Form Analysis") + a
    /// "Form Analysis · {view} (detected) · {fps} fps" subtitle.
    private var headerTitle: some View {
        let hasNum = result.shotNumber != nil
        let title = result.shotNumber.map { "Delivery \($0)" } ?? "Form Analysis"
        let subtitle = hasNum ? "Form Analysis · \(subtitleLine)" : subtitleLine
        return VStack(spacing: 1) {
            Text(title).font(.lsRoboto(20, weight: .semibold)).foregroundStyle(LS.textPrimary)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
        }
    }

    /// Slim honest note that v1 form metrics are early (the view/fps now live in the nav subtitle).
    private var contextHeader: some View {
        Text("Early form analysis (\(result.formFooter?.form_version ?? result.formVersion ?? "form-0.0.0")). Treat these as directional, not exact.")
            .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleLine: String {
        var parts = [viewLabel]
        if let fps = result.formFPS { parts.append("\(Int(fps.rounded())) fps") }
        return parts.joined(separator: " · ")
    }

    private var viewLabel: String {
        switch (result.formView ?? "unknown").lowercased() {
        case "down_lane": return "Side view"
        case "bowler_facing": return "Facing the bowler"
        case "rear": return "Rear view"
        default: return "View not confirmed"
        }
    }

    // MARK: top-level unavailable

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LS.bestEffort)
                Text("Form analysis unavailable").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            }
            Text(unavailableReason).font(.lsCallout).foregroundStyle(LS.textSecondary)
        }
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Form analysis unavailable. \(unavailableReason)")
    }

    private var unavailableReason: String {
        if let note = result.metrics.compactMap({ $0.1.note }).first(where: { !$0.isEmpty }) {
            return note
        }
        return "We couldn't measure your form from this clip. Make sure your full approach and swing are in frame, then record again."
    }

    // MARK: focus card (session focus — shown only when a rule fires)

    private var focusCard: some View {
        let focus = result.formFocus
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FOCUS FOR THIS SESSION").font(.system(size: 11, weight: .semibold)).tracking(0.88).foregroundStyle(LS.link)
                Spacer()
                Text("Form").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.positive)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LS.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if let cue = focus?.cue, !cue.isEmpty {
                Text(cue).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = focus?.comparison_text, !text.isEmpty {
                Text(text).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color(hex: 0xB9C6D9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let drill = focus?.drill, let name = drill.name, !name.isEmpty {
                Text("Drill: \(name)\(drill.how.map { " — \($0)" } ?? "")")
                    .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color(hex: 0xB9C6D9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: KEY POSITIONS (design 3.3)

    /// The four canonical positions and the event that stamps each thumbnail's time. A key not present in
    /// `key_frames` shows an empty "not found" tile — never a guessed frame (design 3.3).
    private static let positions: [(key: String, event: String, label: String)] = [
        ("ball_start", "E2", "Ball start"),
        ("end_pushaway", "E3", "End of pushaway"),
        ("top_of_swing", "E4", "Top of swing"),
        ("release", "E7", "Release"),
    ]

    private var keyPositionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Key positions").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("tap to open the frame").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.positions, id: \.key) { pos in
                    let tile = KeyPositionTile(
                        label: pos.label,
                        timeText: eventTimeText(pos.event),
                        available: result.keyFrames.contains(pos.key),
                        loader: { await fetchFrame(pos.key) })
                    if result.keyFrames.contains(pos.key) {
                        // Tap → the full-frame viewer (Figma 472:4185). Not-found tiles stay non-tappable.
                        NavigationLink { KeyPositionFullView(result: result, startKey: pos.key).environmentObject(model) }
                            label: { tile }
                            .buttonStyle(.plain)
                    } else {
                        tile
                    }
                }
            }
        }
    }

    private func eventTimeText(_ event: String) -> String? {
        guard let t = result.events[event] else { return nil }
        return String(format: "%.2f s", t)
    }

    private func fetchFrame(_ key: String) async -> UIImage? {
        guard let client = try? model.makeClient(),
              let data = try? await client.shotFrame(shotId: result.shotId, key: key) else { return nil }
        return UIImage(data: data)
    }

    // MARK: TIMING CHECKPOINTS (design 3.4)

    private var orderedCheckpoints: [TimingCheckpoint] {
        result.timingCheckpoints.values.sorted { ($0.id ?? "") < ($1.id ?? "") }
    }

    private var timingCheckpointsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Timing vs your baseline").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text(viewLabel).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            .padding(.bottom, 4)
            ForEach(Array(orderedCheckpoints.enumerated()), id: \.offset) { idx, cp in
                TimingCheckpointRow(checkpoint: cp)
                if idx != orderedCheckpoints.count - 1 { Divider().overlay(LS.cardStroke) }
            }
        }
        .lsCard()
    }

    // MARK: SWING TIMING (design 3.4)

    private var swingTimingSection: some View {
        let st = result.swingTiming
        let building = st?.building ?? true
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Swing timing").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                if building {
                    Text("BUILDING").font(.lsCaption.weight(.semibold)).foregroundStyle(LS.bestEffort)
                } else {
                    Text("MEASURED").font(.lsCaption.weight(.semibold)).foregroundStyle(LS.success)
                }
            }

            if let st {
                SwingTimingBar(label: "This delivery", split: st.this_delivery)
                if !building, let base = st.baseline {
                    SwingTimingBar(label: "Your baseline", split: base)
                    phaseDiffGrid(st)
                }
            }

            if building {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(LS.action)
                    Text(st?.prompt ?? "Add one in Profile › Form baseline to compare.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
                .padding(.top, 2)
            } else {
                Text("Baseline from your Profile. Change it in Profile › Form baseline.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    private func phaseDiffGrid(_ st: SwingTiming) -> some View {
        let phases = st.phases ?? Array(SwingTimingBar.phaseOrder)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(phases, id: \.self) { ph in
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.phase_labels?[ph] ?? SwingTimingBar.defaultLabel(ph))
                        .font(.lsCaption.weight(.semibold)).foregroundStyle(SwingTimingBar.color(ph))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(secText(st.this_delivery?[ph]?.value)).font(.lsCaption).foregroundStyle(LS.textPrimary)
                    Text(diffText(st.diff?[ph]?.value)).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func secText(_ v: Double?) -> String { v.map { String(format: "%.2f s", $0) } ?? "—" }
    private func diffText(_ v: Double?) -> String {
        guard let v else { return "—" }
        if abs(v) < 0.005 { return "0.00" }
        return String(format: "%+.2f", v).replacingOccurrences(of: "-", with: "−")
    }

    // MARK: APPROACH & BALANCE (P1 approach metrics)

    /// The measured P1 approach metrics (the design's Approach & balance tiles that aren't M-positions).
    /// Swing-phase splits live in the swing-timing bar; foul line / finish hold / posture live in M1–M7.
    private static let approachKeys: [String] = [
        "step_count", "approach_time", "rhythm_ratio", "ball_start_step", "backswing_height_rel", "drift_boards",
    ]

    private var approachMetrics: [(String, Metric)] {
        Self.approachKeys.compactMap { key in result.metrics.first { $0.0 == key } }
    }

    private var approachSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approach & balance").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(approachMetrics, id: \.0) { key, metric in
                    FormTile(label: FormMetricDisplay.label(key),
                             value: approachValueText(key, metric),
                             status: MetricStatus(metric.status),
                             reason: metric.value == nil ? metric.note : nil)
                }
            }
        }
        .lsCard()
    }

    private func approachValueText(_ key: String, _ m: Metric) -> String {
        guard let v = FormMetricDisplay.formattedValue(key: key, m) else { return "—" }
        if let unit = FormMetricDisplay.unitText(key: key, m) { return "\(v) \(unit)" }
        return v
    }

    // MARK: POSTURE & POSITIONS (M1–M7, design 3.4)

    private var orderedPositions: [MeasuredPosition] {
        result.measuredPositions.values.sorted { ($0.id ?? "") < ($1.id ?? "") }
    }

    private static let positionLabels: [String: String] = [
        "foul_line_distance": "Foul line", "spine_tilt": "Spine tilt", "balance_arm": "Balance arm",
        "shoulder_tilt": "Shoulders", "follow_through": "Follow-through", "finish_hold": "Finish hold",
        "pendulum": "Pendulum",
    ]

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Posture & finish").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(orderedPositions, id: \.id) { pos in
                    FormTile(label: Self.positionLabels[pos.metric ?? ""] ?? MetricDisplay.humanize(pos.metric ?? "—"),
                             value: pos.display ?? "—",
                             status: MetricStatus(pos.status),
                             reason: MetricStatus(pos.status) == .unavailable ? pos.note : nil)
                }
            }
            // Honest reasons for anything best-effort / unavailable (targets + why a view can't measure it).
            let reasons = orderedPositions.compactMap { pos -> String? in
                guard MetricStatus(pos.status) != .measured, let note = pos.note, !note.isEmpty else { return nil }
                let label = Self.positionLabels[pos.metric ?? ""] ?? (pos.metric ?? "")
                return "\(label): \(note)"
            }
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reasons, id: \.self) { r in
                        Text(r).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                    }
                }
            }
        }
        .lsCard()
    }

    // MARK: COACHING CUES (§0.3, text only)

    private func coachingCuesSection(_ cues: CoachingCues) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coaching cues").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            if let note = cues.note, !note.isEmpty {
                Text(note).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            ForEach(cues.cues ?? [], id: \.self) { cue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(LS.action).padding(.top, 6)
                    Text(cue).font(.lsCaption).foregroundStyle(LS.textPrimary)
                }
            }
        }
        .lsCard()
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Text(analyzedText)
            Spacer()
            Text(versionsLine)
        }
        .font(.lsCaption).foregroundStyle(LS.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private var analyzedText: String {
        if let s = result.formFooter?.analyzed_s { return "Analyzed in \(Int(s.rounded())) s" }
        return "Analyzed"
    }

    private var versionsLine: String {
        let f = result.formFooter
        let form = f?.form_version ?? result.formVersion ?? "—"
        let rules = f?.rules_version.map { String(Int($0)) } ?? "—"
        let fund = f?.fundamentals_version ?? "—"
        return "\(form) · rules \(rules) · \(fund)"
    }
}

// MARK: - KEY POSITIONS tile

/// One KEY POSITIONS thumbnail. Fetches a bowler-cropped JPEG from the frame endpoint on appear; shows a
/// faint figure + "not found" when the pose engine didn't locate that position (never a guessed frame).
private struct KeyPositionTile: View {
    let label: String
    let timeText: String?
    let available: Bool
    let loader: () async -> UIImage?

    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LS.raised)
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1)
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "figure.bowling").font(.system(size: 26)).foregroundStyle(LS.borderStrong)
                        if !available || (loaded && image == nil) {
                            Text("not found").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                        } else if let timeText {
                            Text(timeText).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
                if image != nil, let timeText {
                    VStack { Spacer()
                        Text(timeText).font(.lsCaption2).foregroundStyle(LS.textPrimary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(LS.bg.opacity(0.7), in: Capsule())
                            .padding(.bottom, 5)
                    }
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(label).font(.lsCaption).foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .task {
            guard available, !loaded else { return }
            image = await loader()
            loaded = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(available
            ? "\(label)\(timeText.map { ", \($0)" } ?? "")"
            : "\(label), frame not found")
    }
}

// MARK: - Timing checkpoint row

private struct TimingCheckpointRow: View {
    let checkpoint: TimingCheckpoint

    private var verdict: Verdict { Verdict(checkpoint.verdict, status: checkpoint.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(checkpoint.label ?? checkpoint.id ?? "Checkpoint")
                    .font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text(verdict.text).font(.lsCaption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LS.selected, in: Capsule())
                    .foregroundStyle(verdict.color)
            }
            if let detail = detailText {
                Text(detail).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            if verdict != .unavailable, let pos = checkpoint.bar_pos {
                scaleBar(pos)
                HStack {
                    Text("Early"); Spacer(); Text("On time"); Spacer(); Text("Late")
                }
                .font(.lsCaption2).foregroundStyle(LS.textSecondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(checkpoint.label ?? ""), \(verdict.text). \(detailText ?? "")")
    }

    private var detailText: String? {
        if verdict == .unavailable { return checkpoint.note ?? "Not measured" }
        if let d = checkpoint.detail, !d.isEmpty, d != "—" { return d }
        return checkpoint.note
    }

    private func scaleBar(_ pos: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LS.selected).frame(height: 8)
                // on-time band maps to [0.4, 0.6]
                Capsule().fill(LS.successBg).frame(width: w * 0.2, height: 8).offset(x: w * 0.4)
                RoundedRectangle(cornerRadius: 3).fill(LS.textPrimary)
                    .frame(width: 10, height: 14)
                    .offset(x: max(0, min(w - 10, w * CGFloat(pos) - 5)))
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    private enum Verdict: Equatable {
        case early, onTime, late, unavailable
        init(_ raw: String?, status: String?) {
            if (status ?? "").lowercased() == "unavailable" { self = .unavailable; return }
            switch raw?.lowercased() {
            case "early": self = .early
            case "late": self = .late
            case "on_time": self = .onTime
            default: self = .unavailable
            }
        }
        var text: String {
            switch self {
            case .early: return "EARLY"
            case .late: return "LATE"
            case .onTime: return "ON TIME"
            case .unavailable: return "UNAVAILABLE"
            }
        }
        // EARLY / LATE use attention yellow (#F5CD31), not a data color (design 3.7).
        var color: Color {
            switch self {
            case .onTime: return LS.success
            case .early, .late: return LS.dataYellow
            case .unavailable: return LS.unavailable
            }
        }
    }
}

// MARK: - Swing-timing stacked bar

private struct SwingTimingBar: View {
    let label: String
    let split: [String: FlexNum]?

    static let phaseOrder = ["pushaway_time", "backswing_time", "downswing_time", "release_time"]

    static func color(_ phase: String) -> Color {
        switch phase {
        case "pushaway_time": return Color(hex: 0x00A8F5)
        case "backswing_time": return Color(hex: 0x0077B3)
        case "downswing_time": return Color(hex: 0xA55ED0)
        case "release_time": return Color(hex: 0xFA923C)
        default: return LS.textSecondary
        }
    }

    static func defaultLabel(_ phase: String) -> String {
        switch phase {
        case "pushaway_time": return "Pushaway"
        case "backswing_time": return "Backswing"
        case "downswing_time": return "Downswing"
        case "release_time": return "Release"
        default: return phase
        }
    }

    private var total: Double? { split?["total"]?.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.lsCaption).foregroundStyle(LS.textSecondary)
                if let total { Text(String(format: "· %.2f s", total)).font(.lsCaption).foregroundStyle(LS.textSecondary) }
            }
            if hasAnyPhase {
                GeometryReader { geo in
                    let weights = Self.phaseOrder.map { max(0, split?[$0]?.value ?? 0) }
                    let sum = max(weights.reduce(0, +), 0.0001)
                    HStack(spacing: 2) {
                        ForEach(Array(Self.phaseOrder.enumerated()), id: \.offset) { idx, ph in
                            Self.color(ph)
                                .frame(width: max(0, geo.size.width * CGFloat(weights[idx] / sum) - 2))
                        }
                    }
                }
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text("Phase splits not measured for this delivery.")
                    .font(.lsCaption2).foregroundStyle(LS.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceLabel)
    }

    private var hasAnyPhase: Bool {
        Self.phaseOrder.contains { (split?[$0]?.value ?? 0) > 0 }
    }

    private var voiceLabel: String {
        var parts = [label]
        for ph in Self.phaseOrder {
            if let v = split?[ph]?.value { parts.append("\(Self.defaultLabel(ph)) \(String(format: "%.2f", v)) seconds") }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Form metric / position tile

/// One honest tile for the Approach & balance and Posture & positions grids: label, big value, and a
/// status chip (● MEASURED / ◐ BEST EFFORT / ○ UNAVAILABLE). Unavailable → dashed border, "—", + reason.
private struct FormTile: View {
    let label: String
    let value: String
    let status: MetricStatus
    var reason: String?

    private var isUnavailable: Bool { status == .unavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.lsCaption).foregroundStyle(LS.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(isUnavailable ? "—" : value)
                .font(.lsTitle3.weight(.semibold))
                .foregroundStyle(isUnavailable ? LS.textSecondary : LS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            StatusChip(status: status)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isUnavailable ? LS.borderStrong : LS.border,
                              style: StrokeStyle(lineWidth: 1, dash: isUnavailable ? [4, 3] : []))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(isUnavailable ? "unavailable" : value), \(status.label)\(reason.map { ". \($0)" } ?? "")")
    }
}
