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
    // DEC-099: "Use this delivery as my baseline".
    @State private var baselineBusy = false
    @State private var baselineNote: String?

    /// Whether the pose backend itself couldn't run (top-level form status). When true the whole analysis
    /// is unavailable; otherwise the per-section honest states carry the story.
    private var topUnavailable: Bool { (result.formStatus ?? "").lowercased() == "unavailable" }

    /// The scrollable card content (no nav chrome), extracted so a render harness can snapshot it at a fixed
    /// width for the design comparison (02_DESIGN/target_state/compare/form).
    @ViewBuilder var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Show only what was actually measured. Everything that wasn't is ONE plain-English card at the end
            // (names + a tap-to-expand "why"), not dashed "—" tiles and paragraphs of engine notes (2026-11-23).
            if topUnavailable {
                unavailableCard
            } else {
                if !deliveryTimed { notTimedCard }
                if result.formFocus != nil { focusCard }
                if !result.keyFrames.isEmpty { keyPositionsSection }
                if !shownCheckpoints.isEmpty { timingCheckpointsSection }
                if let st = result.swingTiming, Self.measuredPhases(st).count >= 2 { swingTimingSection }
                if !approachTiles.isEmpty { approachSection }
                if !postureTiles.isEmpty { positionsSection }
                if !notMeasured.isEmpty { notMeasuredCard }
                if let cues = result.coachingCues, let list = cues.cues, !list.isEmpty { coachingCuesSection(cues) }
            }
            footer
        }
        .padding(16)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                formContent
            }
            .background(LSBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
            .toolbar {
                ToolbarItem(placement: .principal) { headerTitle }
                ToolbarItem(placement: .confirmationAction) {
                    // DEC-096: live form session → Done returns to the Active (form) session; else dismiss in place.
                    Button("Done") {
                        if model.inLiveCapture { model.exitToSession() } else { dismiss(); model.resetPipeline() }
                    }
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
        let ver = result.formFooter?.form_version ?? result.formVersion
        let verPart = ver.map { " (\($0))" } ?? ""   // show the real engine version, never a fabricated 0.0.0
        return Text("Early form analysis\(verPart). Treat these as directional, not exact.")
            .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleLine: String {
        var parts = [viewLabel]
        if let fps = result.formFPS { parts.append("\(Int(fps.rounded())) fps") }
        return parts.joined(separator: " · ")
    }

    /// Design 3.4: the timing card's right label pairs the measurement status with the view
    /// ("Measured · side view" / "Best effort · rear view").
    private var timingStatusLabel: String {
        let statuses = shownCheckpoints.map { MetricStatus($0.status) }
        let word: String
        if statuses.contains(.measured) && !statuses.contains(.bestEffort) { word = "Measured" }
        else if statuses.contains(.measured) || statuses.contains(.bestEffort) { word = "Best effort" }
        else { return viewLabel }
        return "\(word) · \(viewLabel)"
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
                Text("Tap a position to see the full frame").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.positions, id: \.key) { pos in
                    let tile = KeyPositionTile(
                        label: pos.label,
                        timeText: eventTimeText(pos.event),
                        available: result.keyFrames.contains(pos.key),
                        // skeleton overlay (DEC-082) is normalized to the server's CROPPED still — suppress it on an
                        // on-device local (full-frame) still so the joints don't land off the body. nil → plain still.
                        poseJoints: result.localKeyFrames[pos.key] != nil ? nil : result.keyFramePoses[pos.key],
                        initialImage: result.localKeyFrames[pos.key].flatMap { UIImage(data: $0) },
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
        // Prefer the still extracted on-device from the local clip (no server round-trip, works offline). DEC-131.
        if let local = result.localKeyFrames[key], let img = UIImage(data: local) { return img }
        guard let client = try? model.makeClient(),
              let data = try? await client.shotFrame(shotId: result.shotId, key: key) else { return nil }
        return UIImage(data: data)
    }

    // MARK: TIMING CHECKPOINTS (design 3.4)

    private var orderedCheckpoints: [TimingCheckpoint] {
        result.timingCheckpoints.values.sorted { ($0.id ?? "") < ($1.id ?? "") }
    }
    /// Checkpoints that actually got a reading — unavailable ones go to the "not measured" card instead.
    private var shownCheckpoints: [TimingCheckpoint] {
        orderedCheckpoints.filter { MetricStatus($0.status) != .unavailable }
    }

    private var timingCheckpointsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Timing vs your baseline").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text(timingStatusLabel).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            .padding(.bottom, 4)
            ForEach(Array(shownCheckpoints.enumerated()), id: \.offset) { idx, cp in
                TimingCheckpointRow(checkpoint: cp)
                if idx != shownCheckpoints.count - 1 { Divider().overlay(LS.cardStroke) }
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

            if let st, Self.measuredPhases(st).count >= 2 {
                Button { Task { await useAsBaseline(st) } } label: {
                    HStack(spacing: 6) {
                        if baselineBusy { ProgressView().tint(LS.link) }
                        Text("Use this delivery as my baseline").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(LS.link)
                }
                .buttonStyle(.plain).disabled(baselineBusy).padding(.top, 2)
            }
            if let baselineNote {
                Text(baselineNote).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    /// The measured phase splits of this delivery (seconds), keyed by phase.
    static func measuredPhases(_ st: SwingTiming) -> [String: Double] {
        var out: [String: Double] = [:]
        for ph in FormBaselineView.phases.map(\.key) {
            if let v = st.this_delivery?[ph]?.value, v > 0 { out[ph] = v }
        }
        return out
    }

    /// DEC-099: save this delivery's measured phase splits as the bowler's entered Form baseline. Only measured
    /// phases are saved; a phase this clip didn't measure stays unset (never filled in).
    private func useAsBaseline(_ st: SwingTiming) async {
        baselineBusy = true; baselineNote = nil
        var fb: [String: Any] = ["mode": "entered"]
        for (k, v) in Self.measuredPhases(st) { fb[k] = (v * 100).rounded() / 100 }
        if let t = st.this_delivery?["total"]?.value, t > 0 { fb["total"] = (t * 100).rounded() / 100 }
        do {
            _ = try await model.makeClient().putProfile(["form_baseline": fb])
            baselineNote = "Saved. Future deliveries compare against this one."
        } catch {
            baselineNote = APIClient.fieldError(from: error)?.message ?? "Couldn't save your baseline — try again."
        }
        baselineBusy = false
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
    /// Design 3.4 groups the tiles by MEANING, not data type: "Approach & balance" carries the approach + ball +
    /// slide + finish metrics (9), "Posture & finish" carries only the body-position metrics. `finish_hold`,
    /// `foul_line_distance` and `slide_length` live here even though some are MeasuredPositions server-side.
    private static let approachKeys: [String] = [
        "step_count", "approach_time", "rhythm_ratio", "finish_hold", "backswing_height_rel", "ball_start_step",
        "foul_line_distance", "drift_boards", "slide_length",
    ]
    private static let postureKeys: [String] = ["spine_tilt", "follow_through", "balance_arm", "shoulder_tilt", "pendulum"]

    /// One tile's data, resolved from whichever source holds the key (a Metric, else a MeasuredPosition).
    private struct FormTileData: Identifiable { let id: String; let label: String; let value: String; let status: MetricStatus; let reason: String? }

    private func formTile(_ key: String) -> FormTileData? {
        if let (_, m) = result.metrics.first(where: { $0.0 == key }) {
            return FormTileData(id: key, label: FormMetricDisplay.label(key), value: approachValueText(key, m),
                                status: MetricStatus(m.status), reason: m.value == nil ? m.note : nil)
        }
        if let pos = result.measuredPositions.values.first(where: { ($0.metric ?? "") == key }) ?? result.measuredPositions[key] {
            let st = MetricStatus(pos.status)
            return FormTileData(id: key, label: Self.positionLabels[key] ?? MetricDisplay.humanize(key),
                                value: pos.display ?? "—", status: st,
                                reason: st != .measured ? pos.note : nil)   // best_effort + unavailable → surfaced below
        }
        return nil
    }

    private var allApproachTiles: [FormTileData] { Self.approachKeys.compactMap(formTile) }
    private var allPostureTiles: [FormTileData] { Self.postureKeys.compactMap(formTile) }
    private var approachTiles: [FormTileData] { allApproachTiles.filter { $0.status != .unavailable && $0.value != "—" } }
    private var postureTiles: [FormTileData] { allPostureTiles.filter { $0.status != .unavailable && $0.value != "—" } }

    /// Everything this clip couldn't measure, as (name, plain reason) — deduped, in screen order.
    private struct NotMeasuredItem: Hashable { let name: String; let why: String }
    private var notMeasured: [NotMeasuredItem] {
        var out: [NotMeasuredItem] = []
        var seen = Set<String>()
        func add(_ name: String, _ note: String?) {
            guard seen.insert(name).inserted else { return }
            out.append(NotMeasuredItem(name: name, why: Self.plainReason(note, view: result.formView)))
        }
        for cp in orderedCheckpoints where MetricStatus(cp.status) == .unavailable {
            add(cp.label ?? MetricDisplay.humanize(cp.id ?? ""), cp.note ?? cp.detail)
        }
        for t in allApproachTiles + allPostureTiles where t.status == .unavailable || t.value == "—" {
            add(t.label, t.reason)
        }
        return out
    }

    /// True when at least one swing moment was located. False → the delivery itself couldn't be timed, and the
    /// card leads with that (one sentence + what to do), instead of a wall of "unavailable".
    private var deliveryTimed: Bool { !result.keyFrames.isEmpty || !shownCheckpoints.isEmpty }

    /// Engine notes are written for engineers ("E4", homography, file names). Map them to one short phrase.
    static func plainReason(_ note: String?, view: String?) -> String {
        let n = (note ?? "").lowercased()
        if n.contains("needs a side view") || (n.contains("side view") && (view ?? "") != "down_lane") { return "Needs a side view" }
        if n.contains("rear") && n.contains("needs") || n.contains("from behind") { return "Needs a view from behind" }
        if n.contains("implausible") || n.contains("couldn't be timed") || n.contains("could not be isolated")
            || n.contains("mis-segment") || n.contains("delivery") && n.contains("timed") { return "Couldn't time this delivery" }
        if n.contains("not visible") { return "Body not clearly visible at that moment" }
        if n.contains("not located") || n.contains("not measured") || n.contains("not found") { return "That moment wasn't found in the video" }
        if n.contains("calibrat") || n.contains("homography") || n.contains("validating") || n.contains("scale") { return "Not supported yet" }
        return "Couldn't measure on this clip"
    }

    private var notTimedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LS.bestEffort)
                Text("We couldn't time this delivery").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            Text("None of the key swing moments were found, so timing and swing results are missing. "
                 + "For best results, keep your whole approach, swing and slide in frame from start to finish.")
                .font(.system(size: 14)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lsCard()
    }

    @State private var showWhy = false
    private var notMeasuredCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not measured on this clip").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            Text(notMeasured.map(\.name).joined(separator: " · "))
                .font(.system(size: 14)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { withAnimation { showWhy.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(showWhy ? "Hide why" : "Why?").font(.system(size: 14, weight: .semibold))
                    Image(systemName: showWhy ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(LS.link).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            if showWhy {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notMeasured, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Spacer(minLength: 8)
                            Text(item.why).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .lsCard()
    }

    private var approachSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approach & balance").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(approachTiles) { t in
                    FormTile(label: t.label, value: t.value, status: t.status, reason: t.reason)
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

    private static let positionLabels: [String: String] = [
        "foul_line_distance": "Foul line", "spine_tilt": "Spine tilt", "balance_arm": "Balance arm",
        "shoulder_tilt": "Shoulders", "follow_through": "Follow-through", "finish_hold": "Finish hold",
        "pendulum": "Pendulum",
    ]

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Posture & finish").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(postureTiles) { t in
                    FormTile(label: t.label, value: t.value, status: t.status, reason: t.reason)
                }
            }
        }
        .lsCard()
    }

    // MARK: COACHING CUES (§0.3, text only)

    // General hand/wrist tips (not measured from this clip) — collapsed so they don't read as results.
    @State private var showCues = false
    private func coachingCuesSection(_ cues: CoachingCues) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { showCues.toggle() } } label: {
                HStack {
                    Text("Hand & wrist tips").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Spacer()
                    Image(systemName: showCues ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(LS.link)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showCues {
                Text("General tips — not measured from your video.")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                ForEach(cues.cues ?? [], id: \.self) { cue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(LS.action).padding(.top, 7)
                        Text(cue).font(.system(size: 14)).foregroundStyle(LS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .lsCard()
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(analyzedText).font(.lsCaption2).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Design 3.4: an honest, view-aware note of what this camera angle can and can't measure. Mirrors the
    /// position view-gating (`gate_positions`) so the bowler knows why "— SIDE VIEW" / "— REAR VIEW" appear.
    private var viewCapabilityNote: String? {
        switch (result.formView ?? "").lowercased() {
        case "down_lane":
            return "This clip was recorded from the side, so timing, steps, posture and foul line are measured. "
                + "Drift and balance arm need a view from behind."
        case "rear":
            return "This clip was recorded from behind, so drift and balance arm are measured. Spine tilt and "
                + "foul-line distance need a side view; record from the side to add them."
        default:
            return nil
        }
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
    var poseJoints: [[Double]?]? = nil
    /// On-device still decoded from the local clip — shown synchronously (no async flash) and lets the view
    /// render in a single pass (ImageRenderer screenshots). When set, the server loader is skipped. DEC-131.
    var initialImage: UIImage? = nil
    let loader: () async -> UIImage?

    @State private var image: UIImage?
    @State private var loaded = false

    private var shown: UIImage? { image ?? initialImage }
    // Skeleton is drawn only when the pose found confident joints for this still (never guessed).
    private var hasSkeleton: Bool { (poseJoints?.contains { $0 != nil }) ?? false }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LS.raised)
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1)
                if let image = shown {
                    // scaledToFit (not fill) so the skeleton overlay's aspect-fit mapping lines up with the
                    // bowler-cropped still, matching KeyPositionFullView (DEC-082: thumbnails carry the skeleton).
                    Image(uiImage: image).resizable().scaledToFit()
                        .overlay {
                            if let j = poseJoints, hasSkeleton {
                                SkeletonOverlay(joints: j, imageSize: image.size)
                            }
                        }
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
                if shown != nil, let timeText {
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
            guard available, !loaded, initialImage == nil else { return }   // local still already shown → no fetch
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
            // A verdict is only shown when the checkpoint was actually measured. A missing/empty status, an
            // "unavailable" status, or a nil verdict all collapse to UNAVAILABLE — never a stale "early"/"late"
            // leaking through when its underlying event (E4 top-of-swing, E7 release, …) wasn't located.
            let ok = ["measured", "ok", "best_effort", "low_confidence"].contains((status ?? "").lowercased())
            guard ok else { self = .unavailable; return }
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
