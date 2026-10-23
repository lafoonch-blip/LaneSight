import SwiftUI

/// The Shot card (Shot.dc.html): target vs actual, ball metrics with status, form-from-clip,
/// the sensor question (PATCH /shots/{id}), and the score nudge. Presented after capture.
/// Every number is live from GET /shots/{id} and GET /me/score; nothing is sample data.
struct ShotCardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let result: ShotResult

    @State private var sensors: [Sensor] = []
    @State private var sensorAnswer: String?         // nil = unanswered, "none" or a sensor id / "yes"
    @State private var sensorError: String?
    @State private var helpful: Bool?
    @State private var pendingNotification: AppNotification?

    // Form metric names: anything that looks like approach/swing lives in the form section.
    private static let formKeys: Set<String> = [
        "swing_time", "approach_time", "finish_hold", "backswing", "downswing", "pushaway",
        "rhythm", "step_count", "ball_start_step", "drift", "backswing_height", "release_time",
        "slide", "timing_at_slide",
    ]

    private var metricDict: [String: Metric] { Dictionary(result.metrics, uniquingKeysWith: { a, _ in a }) }
    private var ballMetrics: [(String, Metric)] { result.metrics.filter { !Self.formKeys.contains($0.0) } }
    private var formMetrics: [(String, Metric)] { result.metrics.filter { Self.formKeys.contains($0.0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    targetVsActual
                    ballSection
                    if !formMetrics.isEmpty { formSection }
                    sensorSection
                    ScoreCard(score: result.score, showBreakdown: false)
                    if result.footer != nil { footerSection }
                    helpfulSection
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
            .task { pendingNotification = await model.fetchTopPendingNotification() }
            .fullScreenCover(item: $pendingNotification) { n in
                NavigationStack {
                    CelebrationRouter(notification: n, onClose: { pendingNotification = nil })
                        .environmentObject(model)
                }
            }
        }
    }

    // MARK: score delta + achievement nudges (the analyze job's footer)

    private var footerSection: some View {
        let footer = result.footer
        return VStack(alignment: .leading, spacing: 10) {
            if let delta = footer?.score_delta {
                HStack(spacing: 6) {
                    Image(systemName: delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption)
                    Text("\(delta >= 0 ? "+" : "")\(Fmt.number(delta)) to your score this shot")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(delta >= 0 ? LS.measured : LS.bestEffort)
            }
            if let nudges = footer?.achievement_nudges, !nudges.isEmpty {
                Text("CLOSE TO UNLOCKING").lsEyebrow()
                ForEach(nudges.prefix(3)) { nudge in
                    HStack {
                        Text(nudge.name ?? "").font(.caption).foregroundStyle(LS.textPrimary)
                        Spacer()
                        if let c = nudge.current?.display, let t = nudge.target?.display {
                            Text("\(c) / \(t)").font(.caption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
            }
        }
        .lsCard()
    }

    // MARK: target vs actual

    private var targetVsActual: some View {
        let rows: [(String, String, Metric?)] = [
            ("Feet", model.feetBoardText, nil),
            ("Laydown", "", metricDict["laydown_board"]),
            ("Arrows", model.arrowsBoardText, metricDict["arrows_board"]),
            ("Breakpoint", model.breakpointBoardText, metricDict["breakpoint_board"]),
            ("Entry", "", metricDict["entry_board"]),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("TARGET VS ACTUAL").lsEyebrow()
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").font(.caption2).foregroundStyle(LS.textSecondary).frame(width: 70, alignment: .trailing)
                Text("ACTUAL").font(.caption2).foregroundStyle(LS.textSecondary).frame(width: 70, alignment: .trailing)
            }
            ForEach(rows, id: \.0) { name, target, actual in
                HStack {
                    Text(name).font(.subheadline).foregroundStyle(LS.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(target.isEmpty ? "—" : target)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                    Text(actual?.value.map(Fmt.number) ?? "—")
                        .font(.subheadline.monospacedDigit().bold()).foregroundStyle(LS.textPrimary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
            Text("Target boards are what you set before the shot; actual boards are measured from the clip.")
                .font(.caption2).foregroundStyle(LS.textFaint)
        }
        .lsCard()
    }

    // MARK: ball metrics

    private var ballSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BALL").lsEyebrow()
            if ballMetrics.isEmpty {
                Text("No ball metrics returned for this shot.").font(.callout).foregroundStyle(LS.textSecondary)
            } else {
                ForEach(ballMetrics, id: \.0) { name, metric in
                    MetricRow(name: MetricDisplay.humanize(name), metric: metric)
                    if name != ballMetrics.last?.0 { Divider().overlay(LS.cardStroke) }
                }
            }
        }
        .lsCard()
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
            Text("Was a sensor in the ball?").font(.headline).foregroundStyle(LS.textPrimary)
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
            if let sensorError { Text(sensorError).font(.caption).foregroundStyle(LS.bestEffort) }
            if sensorAnswer != nil && sensorError == nil {
                Label("Saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(LS.measured)
            }
        }
        .lsCard()
    }

    private func selectionRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14).strokeBorder(on ? LS.blue : .clear, lineWidth: 2)
    }

    private var helpfulSection: some View {
        HStack {
            Text("Helpful advice?").font(.subheadline).foregroundStyle(LS.textPrimary)
            Spacer()
            Button { helpful = true } label: {
                Image(systemName: helpful == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(helpful == true ? LS.measured : LS.textSecondary)
            }
            Button { helpful = false } label: {
                Image(systemName: helpful == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(helpful == false ? LS.bestEffort : LS.textSecondary)
            }
        }
        .lsCard()
    }

    private func loadSensors() async {
        sensors = (try? await model.makeClient().listSensors()) ?? []
    }

    private func answer(used: Bool, sensorId: String?, tag: String) async {
        sensorError = nil
        do {
            try await model.answerSensor(shotId: result.shotId, used: used, sensorId: sensorId)
            sensorAnswer = tag
        } catch { sensorError = error.localizedDescription }
    }
}
