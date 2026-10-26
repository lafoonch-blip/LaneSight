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
    @State private var pinsError: String?
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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !result.isForm { resultBadge }
                    if result.captureFarLaneLimited { captureBanner }
                    laneAndTarget
                    nextShotCard
                    if !result.isForm {
                        ringRow
                        allMetricsSection
                    }
                    if !formMetrics.isEmpty { formSection }
                    // v3.7 folds leave/sensor correction into the result badge's "Change" — no standalone
                    // "Was a sensor in the ball?" card on the shot screen (kept wired for the report sheet).
                    if result.isUpload { uploadFooter }
                    ShotNotesView(shotId: result.shotId, isUpload: result.isUpload).environmentObject(model)
                    analyzedFooter
                    if !result.isUpload && !result.isForm { recordNextCTA }
                    Color.clear.frame(height: 1).id("ls-bottom")
                }
                .padding(16)
            }
            #if DEBUG
            .task {
                // Headless preview: optionally scroll to a named anchor so a screenshot can capture the
                // below-the-fold sections (no CLI scroll in this sim). No-op outside the preview harness.
                if let a = ProcessInfo.processInfo.environment["LS_PREVIEW_SCROLL"], !a.isEmpty {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.none) { proxy.scrollTo(a == "bottom" ? "ls-bottom" : a, anchor: .bottom) }
                }
            }
            #endif
            .background(LSBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { headerTitle }
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
    }

    // MARK: next shot — state machine (design 3.7 NextShotStates.dc.html)

    /// The Next Shot card, rendered from the server's insights `state`. Six states (GUARDRAILS 3.7 C.7):
    /// strike_repeat · execution_miss · pins_unknown · no_reliable_data · low_confidence_move · move.
    /// Falls back to the plain "Apply this move" card for an older record that carries a suggested target
    /// but no `state`. Shows nothing when there's neither a state nor an actionable target.
    @ViewBuilder private var nextShotCard: some View {
        switch result.insightsState {
        case "strike_repeat": strikeRepeatCard
        case "execution_miss": executionMissCard
        case "pins_unknown": pinsUnknownCard
        case "no_reliable_data": noReliableDataCard
        case "low_confidence_move": moveCard(lowConfidence: true)
        case "move": moveCard(lowConfidence: false)
        default:
            if let suggested = result.suggestedTarget, suggested.hasBoard { moveCard(lowConfidence: false) }
        }
    }

    /// Shared eyebrow ("NEXT SHOT") in the given accent, optional leading checkmark + trailing chip.
    private func nextShotEyebrow(_ color: Color, check: Bool = false, chip: (String, Color)? = nil) -> some View {
        HStack(spacing: 8) {
            if check { Image(systemName: "checkmark").font(.lsCaption.weight(.bold)) }
            Text("NEXT SHOT").font(.lsCaption.weight(.semibold)).tracking(1.1)
            if let chip {
                Spacer()
                Text(chip.0).font(.lsCaption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LS.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(chip.1)
            }
        }
        .foregroundStyle(color)
    }

    private func stateCard<Content: View>(fill: Color, stroke: Color, dashed: Bool = false,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : [])))
    }

    // STATE · STRIKE (no move)
    private var strikeRepeatCard: some View {
        stateCard(fill: LS.successBg, stroke: LS.success) {
            nextShotEyebrow(LS.success, check: true)
            Text("Strike. Repeat the shot.").font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            if let note = result.insightsNote ?? result.recommendation?.reason, !note.isEmpty {
                Text(note).font(.lsCallout).foregroundStyle(LS.textPrimary)
            }
        }
    }

    // STATE · MISSED YOUR TARGET (repeat, don't move)
    private var executionMissCard: some View {
        stateCard(fill: LS.selected, stroke: LS.borderStrong) {
            nextShotEyebrow(LS.action)
            Text("Same line. Hit your mark.").font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            if let note = result.insightsNote ?? result.recommendation?.reason, !note.isEmpty {
                Text(note).font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            targetStaysBox
        }
    }

    private var targetStaysBox: some View {
        let t = model.sessionTarget
        var parts: [String] = []
        if let f = t.feetBoard { parts.append("F \(Fmt.number(f))") }
        if let a = t.arrowsBoard { parts.append("A \(Fmt.number(a))") }
        if let b = t.breakpointBoard { parts.append("B \(Fmt.number(b))") }
        return Text(parts.isEmpty ? "Target stays the same" : "Target stays · " + parts.joined(separator: " · "))
            .font(.lsCaption.monospacedDigit()).foregroundStyle(LS.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    // STATE · PINS NOT READ (ask the bowler)
    private var pinsUnknownCard: some View {
        stateCard(fill: LS.selected, stroke: LS.borderStrong) {
            nextShotEyebrow(LS.action)
            Text("What did it leave?").font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            Text(result.insightsNote ?? "We couldn't see the pins settle. Tap the result and we'll give your next move.")
                .font(.lsCallout).foregroundStyle(LS.textSecondary)
            if let pinsError { Text(pinsError).font(.lsCaption).foregroundStyle(LS.bestEffort) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                pinButton("Strike", strike: true)
                pinButton("10 pin", pins: [10])
                pinButton("4 / 7 pin", pins: [4, 7])
                pinButton("Split", leave: "split")
                pinButton("Other leave", leave: "other")
                pinButton("Pick pins", leave: "other")   // explicit picker is a later screen; sends "other" for now
            }
        }
    }

    private func pinButton(_ label: String, leave: String? = nil, pins: [Int]? = nil, strike: Bool = false) -> some View {
        Button {
            Task {
                pinsError = nil
                do { try await model.reportPins(shotId: result.shotId, leave: leave, pins: pins, strike: strike) }
                catch { pinsError = error.localizedDescription }
            }
        } label: {
            Text(label).font(.lsSubheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    // STATE · NOT ENOUGH RELIABLE DATA (no move)
    private var noReliableDataCard: some View {
        stateCard(fill: LS.card, stroke: LS.borderStrong, dashed: true) {
            nextShotEyebrow(LS.textSecondary)
            Text("No move this shot").font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            Text(result.insightsNote ?? "The far end of the lane wasn't tracked reliably from this camera spot, so we won't guess at entry board or angle.")
                .font(.lsCallout).foregroundStyle(LS.textSecondary)
            Text("Tip: put the camera behind the approach, centered on your lane, about 5 ft up.")
                .font(.lsCallout).foregroundStyle(LS.textPrimary)
        }
    }

    // STATE · MOVE / LOW-CONFIDENCE MOVE — the actionable "Apply this move" card.

    /// The actionable move card (states `move` and `low_confidence_move`). The headline is built in
    /// BOARDS (never "ft" — SHOT_REVIEW 2026-10-25 #7). For a low-confidence move it carries a
    /// "LOW CONFIDENCE" chip, an "Apply anyway" button, and the cap note. The button applies the
    /// server-computed `suggested_target` (non-null boards only) to the carry-forward target — no board
    /// math is done here. The advice 👍/👎 lives inside this card, as in the design.
    private func moveCard(lowConfidence: Bool) -> some View {
        let rec = result.recommendation
        let suggested = result.suggestedTarget
        return stateCard(fill: LS.selected, stroke: lowConfidence ? LS.borderStrong : LS.action) {
            nextShotEyebrow(LS.action, chip: lowConfidence ? ("◐ LOW CONFIDENCE", LS.bestEffort) : nil)
            Text(moveHeadline(rec, lowConfidence: lowConfidence))
                .font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            if let reason = result.insightsNote ?? rec?.reason, !reason.isEmpty {
                Text(reason).font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            if let expected = rec?.expected, !expected.isEmpty {   // MVP-06: expected effect of the move
                Label(expected, systemImage: "arrow.right.circle")
                    .font(.lsCallout).foregroundStyle(LS.action)
            }
            if let suggested, suggested.hasBoard {
                newTargetSummary(suggested)
                if moveApplied {
                    Label("Applied — it's now your target for the next shot", systemImage: "checkmark.circle.fill")
                        .font(.lsCaption).foregroundStyle(LS.measured)
                } else if lowConfidence {
                    Button { applyMove(suggested) } label: { Text("Apply anyway") }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button { applyMove(suggested) } label: { Text("Apply this move") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Text("Feet and arrows move by the recommended boards; breakpoint is projected from your new line. Edit it on the target chip before your next shot.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            if lowConfidence {
                Text("Moves are at most 2 and 1 boards per shot. Bigger changes need 2 or more shots that agree.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            helpfulRow
        }
    }

    private func applyMove(_ suggested: SuggestedTarget) {
        model.applySuggestedTarget(suggested)
        moveApplied = true
    }

    /// Builds the move headline in boards from the recommendation. Confident: "Move Right: feet 2 boards,
    /// eyes 1 board". Low-confidence: "Maybe: feet 2 boards right, eyes 1 board right". Falls back to the
    /// rec reason / a neutral prompt when the rec carries no board deltas (an advisory speed/release note).
    private func moveHeadline(_ rec: Recommendation?, lowConfidence: Bool) -> String {
        let dir = rec?.direction?.lowercased()
        func boards(_ v: Double?) -> String? { v.map { "\(Fmt.number($0)) board\($0 == 1 ? "" : "s")" } }
        let feet = boards(rec?.move_feet), eyes = boards(rec?.move_target)
        guard let dir, feet != nil || eyes != nil else {
            if let r = rec?.reason, !r.isEmpty { return r }
            return "Adjust your target"
        }
        var segs: [String] = []
        if let feet { segs.append(lowConfidence ? "feet \(feet) \(dir)" : "feet \(feet)") }
        if let eyes { segs.append(lowConfidence ? "eyes \(eyes) \(dir)" : "eyes \(eyes)") }
        let body = segs.joined(separator: ", ")
        return lowConfidence ? "Maybe: \(body)" : "Move \(dir.capitalized): \(body)"
    }

    // MARK: capture-spot banner + upload footer (design 3.7)

    /// Shown above "Target vs actual" when the far lane was limited by the camera spot (capture_quality).
    private var captureBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "camera.fill").font(.lsCallout).foregroundStyle(LS.bestEffort).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("This camera spot limits far-lane numbers").font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text(result.captureReason ?? "Breakpoint, entry and late speed are marked best effort or unavailable.")
                    .font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LS.borderStrong, lineWidth: 1))
    }

    /// Replaces the Score/achievement block on an uploaded clip (DEC-055): uploads are analyzed on their
    /// own and never feed Stats, the LaneSight Score or achievements.
    private var uploadFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.to.line").font(.lsCallout).foregroundStyle(LS.textSecondary)
            Text("Uploaded clip · analyzed on its own. Doesn't count toward Stats, your LaneSight Score or achievements.")
                .font(.lsCaption).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LS.border, lineWidth: 1))
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

    // v3.7 lane card (Figma 413:4132): the simulated lane recreation + legend only. The target-vs-actual
    // comparison moved into the "All metrics" rows as "Target N" sublabels, so there is no table here.
    private var laneAndTarget: some View {
        let t = model.sessionTarget
        let laydown = metricDict["laydown_board"]?.value
        let arrowsAct = metricDict["arrows_board"]?.value
        let bpAct = metricDict["breakpoint_board"]?.value
        let bpDist = metricDict["breakpoint_distance"]?.value
        let entryBoard = metricDict["entry_board"]?.value
        let entryAngle = metricDict["entry_angle"]?.value

        return VStack(alignment: .leading, spacing: 12) {
            LaneRecreationView(
                targetFeet: t.feetBoard, targetArrows: t.arrowsBoard, targetBreakpoint: t.breakpointBoard,
                laydown: laydown, actualArrows: arrowsAct, actualBreakpoint: bpAct,
                breakpointDistanceFt: bpDist, entryBoard: entryBoard, entryAngle: entryAngle,
                handed: model.handed, oilLengthFt: nil)

            legend
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

    // Two-line nav title: "Shot N" (real session ordinal; falls back to "Shot" when absent) + a context
    // subtitle. For a form clip it reads "Form Analysis".
    private var headerTitle: some View {
        let title = result.isForm ? "Form Analysis" : (result.shotNumber.map { "Shot \($0)" } ?? "Shot")
        let subtitle = result.isForm ? "Form Analysis"
            : (result.isUpload ? "Uploaded clip · Shot Analysis" : "Shot Analysis")
        return VStack(spacing: 1) {
            Text(title).font(.lsHeadline).foregroundStyle(LS.textPrimary)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
        }
    }

    // Live in-session CTA (Figma 413:4129 bottom): record the next shot. Dismisses back to capture.
    private var recordNextCTA: some View {
        Button {
            dismiss(); model.resetPipeline()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle.fill").font(.system(size: 14))
                Text(result.shotNumber.map { "Record Shot \($0 + 1)" } ?? "Record next shot")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 4)
    }

    // v3.7 shot result badge (Figma 413:4143). "Change" lets the bowler report the leave when the deck
    // couldn't be read (wiring the report sheet is a follow-up).
    private var resultBadge: some View {
        ShotResultBadge(state: result.insightsState, confidence: result.insightsConfidence) { }
    }

    private func metric(_ name: String) -> Metric? { result.metrics.first { $0.0 == name }?.1 }

    // 3 headline rings (Figma 413:4147): Speed · Rev rate · Accuracy.
    private var ringRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ring("Speed", "ball_speed", unit: "mph", lo: 8, hi: 24, color: LS.action)
            ring("Rev Rate", "rev_rate", unit: "rpm", lo: 100, hi: 600, color: LS.action)
            ring("Accuracy", "accuracy", unit: "", lo: 0, hi: 100, color: LS.success)
        }
    }

    private func ring(_ label: String, _ name: String, unit: String, lo: Double, hi: Double, color: Color) -> some View {
        let m = metric(name)
        let status = MetricStatus(m?.status)
        let v = status == .unavailable ? nil : m?.value
        let valueStr = v.map { String(format: $0 >= 100 ? "%.0f" : "%.1f", $0) } ?? "—"
        return MetricRing(label: label, value: valueStr, unit: v == nil ? "" : unit,
                          fraction: v.map { ($0 - lo) / (hi - lo) } ?? 0, color: color,
                          subLabel: status == .bestEffort ? "best effort" : nil)
    }

    // All-metrics list (Figma 413:4154) — one unified, ordered list: ball speed, the positional boards
    // with their "Target N" sublabels, the read result, then the remaining ball dynamics. Each row is an
    // honest status icon + name/context + value; an unmeasured value shows "—" with the reason.
    private struct ShotMetricRow: Identifiable {
        let id: String
        let name: String
        let sublabel: String?
        let value: String
        let status: MetricStatus
    }

    private func fmtVal(_ m: Metric?, suffix: String = "") -> String {
        guard let m, let v = m.value, MetricStatus(m.status) != .unavailable else { return "—" }
        let unit = suffix.isEmpty ? (m.unit ?? "") : suffix
        return unit.isEmpty ? Fmt.number(v) : "\(Fmt.number(v)) \(unit)"
    }

    /// Positional boards read as a bare board number ("15.1") — the "board" unit is implied by the lane.
    private func posVal(_ m: Metric?) -> String {
        guard let m, let v = m.value, MetricStatus(m.status) != .unavailable else { return "—" }
        return Fmt.number(v)
    }

    private func target(_ v: Double?) -> String? { v.map { "Target \(Fmt.number($0))" } }

    private var shotMetricRows: [ShotMetricRow] {
        let t = model.sessionTarget
        var rows: [ShotMetricRow] = []
        var used = Set<String>()
        func status(_ key: String) -> MetricStatus { MetricStatus(metricDict[key]?.status) }

        // Ball speed (headline dynamic).
        if let m = metricDict["ball_speed"] {
            used.insert("ball_speed")
            rows.append(.init(id: "ball_speed", name: "Ball speed", sublabel: m.note,
                              value: fmtVal(m, suffix: "mph"), status: status("ball_speed")))
        }
        // Positional boards carry their set target as the sublabel.
        if let m = metricDict["arrows_board"] {
            used.insert("arrows_board")
            rows.append(.init(id: "arrows_board", name: "Arrows", sublabel: target(t.arrowsBoard),
                              value: posVal(m), status: status("arrows_board")))
        }
        if let m = metricDict["breakpoint_board"] {
            used.insert("breakpoint_board"); used.insert("breakpoint_distance")
            var v = posVal(m)
            if v != "—", let d = metricDict["breakpoint_distance"]?.value { v += " at \(Int(d.rounded())) ft" }
            rows.append(.init(id: "breakpoint_board", name: "Breakpoint", sublabel: target(t.breakpointBoard),
                              value: v, status: status("breakpoint_board")))
        }
        if let m = metricDict["entry_board"] {
            used.insert("entry_board"); used.insert("entry_angle")
            var v = posVal(m)
            if v != "—", let a = metricDict["entry_angle"]?.value { v += " · \(String(format: "%.1f", a))°" }
            rows.append(.init(id: "entry_board", name: "Entry board · angle", sublabel: metricDict["entry_board"]?.note,
                              value: v, status: status("entry_board")))
        }
        // Read result (mirrors the badge up top).
        let res = ShotResultBadge(state: result.insightsState, confidence: result.insightsConfidence, onChange: {}).resultText
        rows.append(.init(id: "result", name: "Result", sublabel: res.sub,
                          value: res.title, status: res.title == "Not read" ? .unavailable : .measured))
        // Remaining ball dynamics (rev rate, loft, …) in their returned order.
        for (name, m) in ballMetrics where !used.contains(name) {
            rows.append(.init(id: name, name: MetricDisplay.humanize(name), sublabel: m.note,
                              value: fmtVal(m), status: MetricStatus(m.status)))
        }
        return rows
    }

    private var allMetricsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All metrics").font(.system(size: 15, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            let rows = shotMetricRows
            ForEach(rows) { r in
                MetricStatusRowV37(name: r.name, sublabel: r.sublabel, value: r.value, status: r.status)
                if r.id != rows.last?.id {
                    Divider().overlay(LS.border).padding(.leading, 40)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
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
                if !isUnavailable, let band = Fmt.band(metric) {
                    Text(band).font(.lsCaption.weight(.semibold)).foregroundStyle(LS.textSecondary)
                }
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
