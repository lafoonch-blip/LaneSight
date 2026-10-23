import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var score: Loadable<ScoreResponse> = .idle
    @State private var history: [ScoreResponse] = []
    @State private var throwStats: Loadable<StatsResponse> = .idle
    @State private var formStats: Loadable<StatsResponse> = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("View", selection: $tab) {
                        Text("Score").tag(0)
                        Text("Throw").tag(1)
                        Text("Form").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case 0: scoreTab
                    case 1: throwTab
                    default: formTab
                    }
                    Spacer(minLength: 8)
                }
                .padding(16)
            }
            .background(LSBackground())
            .navigationTitle("Stats")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await loadScore() }
            .task(id: tab) { await loadForTab() }
            .refreshable { await loadScore(); await loadForTab() }
        }
    }

    // MARK: Score

    private var scoreTab: some View {
        LoadableView(state: score, retry: { Task { await loadScore() } }) { s in
            VStack(alignment: .leading, spacing: 14) {
                ScoreCard(score: s, history: history)
                historyCard
            }
        }
    }

    private var historyCard: some View {
        let scored = history.compactMap { $0.eligible == true ? $0.score : nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("SCORE HISTORY").lsEyebrow()
            if scored.isEmpty {
                Text("No eligible score snapshots yet. Your history fills in as you log shots.")
                    .font(.caption).foregroundStyle(LS.textSecondary)
            } else {
                HStack {
                    KPITile(label: "Snapshots", value: "\(history.count)")
                    KPITile(label: "Best", value: Fmt.intStr(scored.max()))
                    KPITile(label: "Latest", value: Fmt.intStr(scored.last))
                }
            }
        }
        .lsCard()
    }

    // MARK: Throw

    private var throwTab: some View {
        LoadableView(state: throwStats, retry: { Task { await loadThrow() } }) { s in
            if s.empty == true || (s.n_shots ?? 0) == 0 {
                emptyCard("Throw stats need more shots",
                          "Record shots and they'll roll up here — speed, rev rate, entry board, breakpoint and angle, with coverage and top failure reasons.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    averagesGrid(s, order: ["ball_speed", "rev_rate", "entry_board", "entry_angle",
                                            "breakpoint_board", "arrows_board"],
                                 units: ["ball_speed": "mph avg", "rev_rate": "rpm avg", "entry_board": "board avg",
                                         "entry_angle": "deg avg", "breakpoint_board": "board avg", "arrows_board": "board avg"])
                    coverageCard(s)
                    failureReasonsCard(s)
                    sampleNote(s)
                }
            }
        }
    }

    // MARK: Form

    private var formTab: some View {
        LoadableView(state: formStats, retry: { Task { await loadForm() } }) { s in
            if s.empty == true {
                emptyCard("Form stats need form clips",
                          s.note ?? "Form metrics require form clips and supported camera angles. Record in Form mode and they'll appear here.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    coverageCard(s)
                    failureReasonsCard(s)
                    sampleNote(s)
                    Text("Form stats are diagnostic and are not part of your LaneSight Score.")
                        .font(.caption).foregroundStyle(LS.textFaint)
                }
            }
        }
    }

    // MARK: shared pieces (all values live from /me/stats)

    private func averagesGrid(_ s: StatsResponse, order: [String], units: [String: String]) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(order, id: \.self) { key in
                let avg = s.averages?[key]
                let cov = s.metric_coverage?[key]
                VStack(alignment: .leading, spacing: 2) {
                    Text(MetricDisplay.humanize(key)).font(.caption2).foregroundStyle(LS.textSecondary).lineLimit(1)
                    if let mean = avg?.mean {
                        Text(Fmt.number(mean)).font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(LS.textPrimary)
                        Text(units[key] ?? "avg").font(.caption2).foregroundStyle(LS.textSecondary)
                    } else {
                        Text("—").font(.title3.weight(.heavy)).foregroundStyle(LS.textFaint)
                        Text("no measured shots").font(.caption2).foregroundStyle(LS.textFaint)
                    }
                    if let pct = cov?.pct { Text("\(Int(pct))% measured").font(.caption2).foregroundStyle(coverageColor(pct)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lsCard(padding: 12)
            }
        }
    }

    private func coverageCard(_ s: StatsResponse) -> some View {
        let rows = (s.metric_coverage ?? [:]).sorted { ($0.value.pct ?? -1) > ($1.value.pct ?? -1) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("METRIC COVERAGE").lsEyebrow()
                Spacer()
                Text("% of shots measured").font(.caption2).foregroundStyle(LS.textSecondary)
            }
            ForEach(rows, id: \.key) { key, cov in
                HStack(spacing: 10) {
                    Text(MetricDisplay.humanize(key)).font(.caption).foregroundStyle(LS.textPrimary)
                        .frame(width: 104, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(coverageColor(cov.pct))
                                .frame(width: geo.size.width * CGFloat((cov.pct ?? 0) / 100))
                        }
                    }
                    .frame(height: 8)
                    Text(cov.pct.map { "\(Int($0))%" } ?? "—")
                        .font(.caption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(MetricDisplay.humanize(key)) measured on \(cov.pct.map { "\(Int($0)) percent" } ?? "no") shots")
            }
        }
        .lsCard()
    }

    @ViewBuilder private func failureReasonsCard(_ s: StatsResponse) -> some View {
        if let reasons = s.top_failure_reasons, !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("TOP FAILURE REASONS").lsEyebrow()
                ForEach(reasons) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled").font(.system(size: 7)).foregroundStyle(LS.bestEffort)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(MetricDisplay.humanize(r.metric ?? "")).font(.subheadline).foregroundStyle(LS.textPrimary)
                            Text(r.reason ?? "").font(.caption2).foregroundStyle(LS.textSecondary)
                        }
                        Spacer()
                        Text("\(r.count ?? 0)×").font(.caption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                    }
                }
            }
            .lsCard()
        }
    }

    private func sampleNote(_ s: StatsResponse) -> some View {
        Text("Based on \(s.n_shots ?? 0) shot\((s.n_shots ?? 0) == 1 ? "" : "s") in range.")
            .font(.caption2).foregroundStyle(LS.textFaint)
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "hourglass").font(.headline).foregroundStyle(LS.textPrimary)
            Text(message).font(.callout).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private func coverageColor(_ pct: Double?) -> Color {
        guard let pct else { return LS.unavailable }
        if pct >= 80 { return LS.measured }
        if pct > 0 { return LS.bestEffort }
        return LS.unavailable
    }

    // MARK: loading

    private func loadForTab() async {
        if tab == 1 { await loadThrow() }
        else if tab == 2 { await loadForm() }
    }

    private func loadScore() async {
        score = .loading
        do {
            let client = try model.makeClient()
            async let s = client.score()
            async let h = client.scoreHistory()
            let (sv, hv) = try await (s, h)
            history = hv
            score = .loaded(sv)
        } catch { score = .failed(error.localizedDescription) }
    }

    private func loadThrow() async {
        throwStats = .loading
        do { throwStats = .loaded(try await model.makeClient().stats(view: "throw", range: nil)) }
        catch { throwStats = .failed(error.localizedDescription) }
    }

    private func loadForm() async {
        formStats = .loading
        do { formStats = .loaded(try await model.makeClient().stats(view: "form", range: nil)) }
        catch { formStats = .failed(error.localizedDescription) }
    }
}
