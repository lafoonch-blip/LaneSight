import SwiftUI

/// The Shot card (Shot.dc.html, design 3.5/3.6): the simulated lane recreation, target-vs-actual table,
/// the next-shot move ("Apply this move"), the ball-metrics grid with honest status, the sensor
/// question (PATCH /shots/{id}), the score/achievement nudges, the bowler's notes (autosaved to
/// /feedback), and the analyzed-in/versions footer. Every number is live from GET /shots/{id},
/// GET /me/score and the session target; nothing is sample data, and an unmeasured value shows "—".
struct ShotCardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: ShotResult

    @State private var sensors: [Sensor] = []
    @State private var sensorAnswer: String?         // nil = unanswered, "none" or a sensor id / "yes"
    @State private var sensorError: String?
    @State private var helpful: Bool?
    @State private var pendingNotification: AppNotification?
    @State private var moveApplied = false
    @State private var coreVersion: String?
    @State private var rulesVersion: String?

    // Form metric names: anything that looks like approach/swing lives in the form section.
    private static let formKeys: Set<String> = [
        "swing_time", "approach_time", "finish_hold", "backswing", "downswing", "pushaway",
        "rhythm", "step_count", "ball_start_step", "drift", "backswing_height", "release_time",
        "slide", "timing_at_slide",
        "pushaway_time", "backswing_time", "downswing_time", "rhythm_ratio",
        "backswing_height_rel", "drift_boards",
    ]
    // Positional boards are shown in the lane + target/actual table, not in the ball-dynamics grid.
    private static let positionalKeys: Set<String> = [
        "laydown_board", "arrows_board", "breakpoint_board", "entry_board",
        "board_at_0ft", "board_at_7ft", "board_at_15ft", "breakpoint_distance",
    ]

    private var metricDict: [String: Metric] { Dictionary(result.metrics, uniquingKeysWith: { a, _ in a }) }
    private var ballMetrics: [(String, Metric)] {
        result.metrics.filter { !Self.formKeys.contains($0.0) && !Self.positionalKeys.contains($0.0) }
    }
    private var formMetrics: [(String, Metric)] { result.metrics.filter { Self.formKeys.contains($0.0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let suggested = result.suggestedTarget, suggested.hasBoard { applyMoveSection(suggested) }
                    laneAndTarget
                    ballSection
                    if !formMetrics.isEmpty { formSection }
                    sensorSection
                    ScoreCard(score: result.score, showBreakdown: false)
                    if result.footer != nil { scoreNudges }
                    ShotNotesView(shotId: result.shotId, isUpload: isUpload).environmentObject(model)
                    analyzedFooter
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss(); model.resetPipeline() }
                }
            }
            .task { await loadSensors() }
            .task { await loadVersions() }
            .task { pendingNotification = await model.fetchTopPendingNotification() }
            .fullScreenCover(item: $pendingNotification) { n in
                NavigationStack {
                    CelebrationRouter(notification: n, onClose: { pendingNotification = nil })
                        .environmentObject(model)
                }
            }
        }
    }

    private var isUpload: Bool { false }     // this card is shown for live shots; uploads seed the same flow

    // MARK: next shot ("Apply this move")

    /// The server's actionable move inside the cyan-accent card (design 3.5). The button applies the
    /// server-computed `suggested_target` (non-null boards only) to the carry-forward target. No board
    /// math is done here. The advice 👍/👎 lives inside this card, as in the design.
    private func applyMoveSection(_ suggested: SuggestedTarget) -> some View {
        let rec = result.recommendation
        let direction = (rec?.direction ?? suggested.direction)?.capitalized
        let moveFeet = rec?.move_feet ?? suggested.move_feet
        let headline: String = {
            if let direction, let moveFeet { return "Move \(direction) \(Fmt.number(moveFeet)) ft" }
            if let direction { return "Move \(direction)" }
            return "Adjust your target"
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right").font(.lsCaption.weight(.bold))
                Text("NEXT SHOT").font(.lsCaption.weight(.semibold)).tracking(1.1)
            }
            .foregroundStyle(LS.action)
            Text(headline).font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            if let reason = rec?.reason, !reason.isEmpty {
                Text(reason).font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            newTargetSummary(suggested)
            if moveApplied {
                Label("Applied — it's now your target for the next shot", systemImage: "checkmark.circle.fill")
                    .font(.lsCaption).foregroundStyle(LS.measured)
            } else {
                Button {
                    model.applySuggestedTarget(suggested)
                    moveApplied = true
                } label: {
                    Text("Apply this move")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Text("Feet and arrows move by the recommended boards; breakpoint is projected from your new line. Edit it on the target chip before your next shot.")
                .font(.lsCaption).foregroundStyle(LS.textSecondary)
            helpfulRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.selected, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LS.action, lineWidth: 1))
    }

    private func newTargetSummary(_ s: SuggestedTarget) -> some View {
        HStack(spacing: 0) {
            Text("New target · ").foregroundStyle(LS.textSecondary)
            if let f = s.feet_board { Text("F \(Fmt.number(f)) · ").foregroundStyle(LS.textSecondary) }
            if let a = s.arrows_board { Text("A \(Fmt.number(a)) · ").foregroundStyle(LS.textSecondary) }
            if let b = s.breakpoint_board {
                Text("B \(Fmt.number(b)) suggested").foregroundStyle(LS.action)
            }
        }
        .font(.lsCaption.monospacedDigit())
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    private var helpfulRow: some View {
        HStack(spacing: 8) {
            Text("Helpful advice?").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
            Spacer()
            Button { helpful = true } label: {
                Image(systemName: helpful == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(helpful == true ? LS.measured : LS.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(LS.selected, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
            }
            .accessibilityLabel("Helpful")
            Button { helpful = false } label: {
                Image(systemName: helpful == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(helpful == false ? LS.bestEffort : LS.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(LS.selected, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
            }
            .accessibilityLabel("Not helpful")
        }
    }

    // MARK: lane recreation + target vs actual

    private var laneAndTarget: some View {
        let t = model.sessionTarget
        let laydown = metricDict["laydown_board"]?.value
        let arrowsAct = metricDict["arrows_board"]?.value
        let bpAct = metricDict["breakpoint_board"]?.value
        let bpDist = metricDict["breakpoint_distance"]?.value
        let entryBoard = metricDict["entry_board"]?.value
        let entryAngle = metricDict["entry_angle"]?.value

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Target vs actual").font(.lsHeadline).foregroundStyle(LS.textPrimary)
                Spacer()
                if let badge = onTargetBadge(targetArrows: t.arrowsBoard, actualArrows: arrowsAct,
                                             targetBreakpoint: t.breakpointBoard, actualBreakpoint: bpAct) {
                    Text(badge.text)
                        .font(.lsCaption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(badge.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(badge.color)
                }
            }

            LaneRecreationView(
                targetFeet: t.feetBoard, targetArrows: t.arrowsBoard, targetBreakpoint: t.breakpointBoard,
                laydown: laydown, actualArrows: arrowsAct, actualBreakpoint: bpAct,
                breakpointDistanceFt: bpDist, entryBoard: entryBoard, entryAngle: entryAngle,
                handed: model.handed, oilLengthFt: nil)

            legend

            targetTable(target: t, laydown: laydown, arrowsAct: arrowsAct, bpAct: bpAct,
                        entryBoard: entryBoard, entryAngle: entryAngle, bpDist: bpDist)
        }
        .lsCard()
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(dashed: true, color: Color(hex: 0x33BFFF), label: "Target line")
            legendItem(dashed: false, color: Color(hex: 0x3DEB7C), label: "Your line")
            legendItem(dashed: false, color: Color(hex: 0xC08BFF), label: "House shot")
        }
        .frame(maxWidth: .infinity)
        .font(.lsCaption).foregroundStyle(LS.textSecondary)
        .accessibilityHidden(true)      // the lane view carries the combined description
    }

    private func legendItem(dashed: Bool, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Rectangle().fill(color).frame(width: 16, height: 2)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label)
        }
    }

    private func targetTable(target t: ShotIntent, laydown: Double?, arrowsAct: Double?, bpAct: Double?,
                             entryBoard: Double?, entryAngle: Double?, bpDist: Double?) -> some View {
        func s(_ v: Double?) -> String { v.map(Fmt.number) ?? "—" }
        let rows: [TableRow] = [
            TableRow(name: "Feet", tgt: s(t.feetBoard), act: "—", actColor: LS.textSecondary),
            TableRow(name: "Laydown", tgt: "—", act: s(laydown), actColor: LS.textPrimary),
            TableRow(name: "Arrows", tgt: s(t.arrowsBoard), act: s(arrowsAct),
                     actColor: matchColor(t.arrowsBoard, arrowsAct)),
            TableRow(name: "Breakpoint", tgt: s(t.breakpointBoard), act: s(bpAct),
                     actColor: matchColor(t.breakpointBoard, bpAct)),
            TableRow(name: "Entry", tgt: "—", act: s(entryBoard),
                     actColor: entryBoard != nil ? LS.textPrimary : LS.textSecondary),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("TGT").font(.lsCaption2).foregroundStyle(LS.textSecondary).frame(width: 56, alignment: .trailing)
                Text("ACT").font(.lsCaption2).foregroundStyle(LS.textSecondary).frame(width: 56, alignment: .trailing)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.name).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.tgt).font(.lsSubheadline.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        .frame(width: 56, alignment: .trailing)
                    Text(row.act).font(.lsSubheadline.monospacedDigit().weight(.semibold)).foregroundStyle(row.actColor)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            Divider().overlay(LS.cardStroke)
            Text(accuracySummary(target: t, arrowsAct: arrowsAct, bpAct: bpAct, bpDist: bpDist))
                .font(.lsCaption).foregroundStyle(LS.textSecondary)
            if let a = entryAngle {
                Text("Entry angle \(String(format: "%.1f", a))° ✓").font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
    }

    private struct TableRow: Identifiable {
        let name: String; let tgt: String; let act: String; let actColor: Color
        var id: String { name }
    }

    /// Green when the measured board matches the set target within a board, amber when it diverges,
    /// plain when either side is missing (no fabricated comparison).
    private func matchColor(_ target: Double?, _ actual: Double?) -> Color {
        guard let t = target, let a = actual else { return LS.textPrimary }
        return abs(a - t) <= 1 ? LS.measured : LS.bestEffort
    }

    private func onTargetBadge(targetArrows: Double?, actualArrows: Double?,
                               targetBreakpoint: Double?, actualBreakpoint: Double?)
        -> (text: String, color: Color)? {
        var offs: [Double] = []
        if let t = targetArrows, let a = actualArrows { offs.append(abs(a - t)) }
        if let t = targetBreakpoint, let a = actualBreakpoint { offs.append(abs(a - t)) }
        guard let worst = offs.max() else { return nil }      // no target set → no badge
        if worst <= 1 { return ("ON TARGET", LS.measured) }
        return ("OFF \(Int(worst.rounded())) BOARDS", LS.bestEffort)
    }

    /// Honest boards-off summary from measured vs set boards. No fabricated accuracy score.
    private func accuracySummary(target t: ShotIntent, arrowsAct: Double?, bpAct: Double?, bpDist: Double?) -> String {
        var parts: [String] = []
        if let ta = t.arrowsBoard, let a = arrowsAct { parts.append("Arrows \(Fmt.number(abs(a - ta)))") }
        if let tb = t.breakpointBoard, let b = bpAct { parts.append("breakpoint \(Fmt.number(abs(b - tb)))") }
        if parts.isEmpty {
            return "Set a target before the shot to see how far your boards were off."
        }
        var s = parts.joined(separator: " · ") + " boards off"
        if let d = bpDist { s += " (breakpoint at \(Int(d.rounded())) ft)" }
        return s
    }

    // MARK: ball metrics grid

    private var ballSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BALL").lsEyebrow()
            if ballMetrics.isEmpty {
                Text("No ball metrics returned for this shot.").font(.lsCallout).foregroundStyle(LS.textSecondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(ballMetrics, id: \.0) { name, metric in
                        BallMetricTile(name: MetricDisplay.humanize(name), metric: metric)
                    }
                }
                if let note = unavailableNote {
                    Text(note).font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            }
        }
        .lsCard()
    }

    /// Surface the first honest note from any unavailable/best-effort ball metric (e.g. "a strip of tape
    /// on the ball helps"), if the backend provided one.
    private var unavailableNote: String? {
        ballMetrics.compactMap { $0.1.note }.first { !$0.isEmpty }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FORM FROM THIS CLIP").lsEyebrow()
            ForEach(formMetrics, id: \.0) { name, metric in
                MetricRow(name: MetricDisplay.humanize(name), metric: metric)
                if name != formMetrics.last?.0 { Divider().overlay(LS.cardStroke) }
            }
        }
        .lsCard()
    }

    // MARK: sensor question

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was a sensor in the ball?").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            HStack {
                Button("No") { Task { await answer(used: false, sensorId: nil, tag: "none") } }
                    .buttonStyle(SecondaryButtonStyle())
                    .overlay(selectionRing(sensorAnswer == "none"))
                if sensors.isEmpty {
                    Button("Yes") { Task { await answer(used: true, sensorId: nil, tag: "yes") } }
                        .buttonStyle(SecondaryButtonStyle())
                        .overlay(selectionRing(sensorAnswer == "yes"))
                } else {
                    Menu {
                        ForEach(sensors) { s in
                            Button(s.name ?? "Sensor") {
                                Task { await answer(used: true, sensorId: s.id, tag: s.id) }
                            }
                        }
                    } label: {
                        Text("Yes · pick sensor").frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .overlay(selectionRing(sensors.contains { $0.id == sensorAnswer }))
                }
            }
            if let sensorError { Text(sensorError).font(.lsCaption).foregroundStyle(LS.bestEffort) }
            if sensorAnswer != nil && sensorError == nil {
                Label("Saved with this shot so readings can be compared later. Remembered for the next shot.",
                      systemImage: "checkmark.circle.fill")
                    .font(.lsCaption).foregroundStyle(LS.measured)
            } else {
                Text("Saved with this shot so readings can be compared later. Remembered for the next shot.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .lsCard()
    }

    private func selectionRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8).strokeBorder(on ? LS.blue : .clear, lineWidth: 2)
    }

    // MARK: score delta + achievement nudges

    private var scoreNudges: some View {
        let footer = result.footer
        return VStack(alignment: .leading, spacing: 10) {
            if let delta = footer?.score_delta {
                HStack(spacing: 6) {
                    Image(systemName: delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.lsCaption)
                    Text("\(delta >= 0 ? "+" : "")\(Fmt.number(delta)) to your score this shot")
                        .font(.lsSubheadline.weight(.semibold))
                }
                .foregroundStyle(delta >= 0 ? LS.measured : LS.bestEffort)
            }
            if let nudges = footer?.achievement_nudges, !nudges.isEmpty {
                Text("CLOSE TO UNLOCKING").lsEyebrow()
                ForEach(nudges.prefix(3)) { nudge in
                    HStack {
                        Text(nudge.name ?? "").font(.lsCaption).foregroundStyle(LS.textPrimary)
                        Spacer()
                        if let c = nudge.current?.display, let t = nudge.target?.display {
                            Text("\(c) / \(t)").font(.lsCaption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
            }
        }
        .lsCard()
    }

    // MARK: analyzed-in / versions footer

    private var analyzedFooter: some View {
        HStack {
            Text("Analyzed in \(analyzedDuration ?? "—")")
            Spacer()
            Text(versionsLine)
        }
        .font(.lsCaption).foregroundStyle(LS.textSecondary)
        .accessibilityElement(children: .combine)
    }

    /// Job timing isn't carried onto the result record in this build, so it's shown as "—" rather than a
    /// fabricated value.
    private var analyzedDuration: String? { nil }

    private var versionsLine: String {
        "core \(coreVersion ?? "—") · rules \(rulesVersion ?? "—") · \(result.score.formula_version ?? "—")"
    }

    // MARK: data loads

    private func loadSensors() async {
        sensors = (try? await model.makeClient().listSensors()) ?? []
    }

    private func loadVersions() async {
        guard let client = try? model.makeClient(), let health = try? await client.health() else { return }
        coreVersion = health.versions?["core"]
        rulesVersion = health.versions?["rules"]
    }

    private func answer(used: Bool, sensorId: String?, tag: String) async {
        sensorError = nil
        do {
            try await model.answerSensor(shotId: result.shotId, used: used, sensorId: sensorId)
            sensorAnswer = tag
        } catch { sensorError = error.localizedDescription }
    }
}

// MARK: - Ball metric tile (3-col grid, honest status)

/// One ball-dynamics metric tile matching design 3.5: label, big value + unit, and a status pill —
/// ● MEASURED (green) / ◐ BEST EFFORT (amber) / ○ UNAVAILABLE (faint, dashed border, "—" value).
private struct BallMetricTile: View {
    let name: String
    let metric: Metric

    private var status: MetricStatus { MetricStatus(metric.status) }
    private var isUnavailable: Bool { status == .unavailable || metric.value == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.lsCaption).foregroundStyle(LS.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(isUnavailable ? "—" : Fmt.value(metric))
                    .font(.lsTitle3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isUnavailable ? LS.textSecondary : LS.textPrimary)
                if !isUnavailable, let unit = metric.unit, !unit.isEmpty {
                    Text(unit).font(.lsCaption.weight(.semibold)).foregroundStyle(LS.textSecondary)
                }
            }
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
        .accessibilityLabel("\(name), \(isUnavailable ? "unavailable" : "\(Fmt.value(metric)) \(metric.unit ?? "")"), \(status.label)")
    }
}
