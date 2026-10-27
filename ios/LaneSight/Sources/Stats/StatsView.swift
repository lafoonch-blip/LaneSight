import SwiftUI

struct StatsView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var score: Loadable<ScoreResponse> = .idle
    @State private var history: [ScoreResponse] = []
    @State private var breakdown: ScoreBreakdown?
    @State private var throwStats: Loadable<StatsResponse> = .idle
    @State private var formStats: Loadable<StatsResponse> = .idle
    @State private var equipment: Loadable<EquipmentStats> = .idle

    // DEC-085: tab order Shot · Form · Score · Arsenal (was Score · Shot · Form · Equipment, DEC-073).
    // Stats opens on Shot (the most-used view), so a new bowler lands on real shot values, not an empty card.
    private let tabs = ["Shot", "Form", "Score", "Arsenal"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LSTabHeader(title: "Stats")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        filterChips
                        tabBar
                        switch tab {
                        case 0: throwTab
                        case 1: formTab
                        case 2: scoreTab
                        default: equipmentTab    // Arsenal
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
                .task { await loadScore() }
                .task(id: tab) { await loadForTab() }
                .refreshable { await loadScore(); await loadForTab() }
                #if DEBUG
                .onAppear { if let t = ProcessInfo.processInfo.environment["LS_PREVIEW_TAB"], let i = Int(t) { tab = i } }
                #endif
            }
            .background(LSBackground())
            .navigationBarHidden(true)
        }
    }

    // MARK: tab bar + filters

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { i in
                Button { tab = i } label: {
                    Text(tabs[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tab == i ? LS.onAction : LS.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(tab == i ? LS.action : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(LS.card, in: Capsule())
        .overlay(Capsule().strokeBorder(LS.border, lineWidth: 1))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            filterChip("Last 90 days")
            filterChip("All balls")
            filterChip("All patterns")
            Spacer(minLength: 0)
        }
    }

    // The filters are display for the MVP: the Score window is fixed at 90 days and the staged views are
    // unfiltered. Shown for parity with the design; wiring ball/pattern filtering is a later enhancement.
    private func filterChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(LS.textPrimary)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(LS.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(LS.card, in: Capsule())
        .overlay(Capsule().strokeBorder(LS.border, lineWidth: 1))
    }

    // MARK: Score

    private var scoreTab: some View {
        LoadableView(state: score, retry: { Task { await loadScore() } }) { s in
            if s.eligible == true {
                VStack(alignment: .leading, spacing: 12) {
                    ScoreCard(score: s, history: history, showBreakdown: false)
                    scoreTrendCard(s)
                    provisionalNote
                    scorePartsSection(s)
                }
            } else {
                scoreBuildingTab(s)      // DEC-085: the real Score screen in a building/locked state
            }
        }
    }

    // MARK: Score — building state (DEC-085; mirrors the Home building card, DEC-083)

    /// have/need for each weighted part, from the live GET /me/score eligibility (never mock counts).
    private func elig(_ key: String) -> (have: Int, need: Int, met: Bool) {
        let e = score.value?.eligibility?[key]
        return (e?.have ?? 0, e?.need ?? 0, e?.met ?? false)
    }
    private var unlockPct: Double {
        let keys = ["s_perf", "a_acc", "c_cons", "p_power"]
        let have = keys.reduce(0.0) { $0 + Double(min(elig($1).have, elig($1).need)) }
        let need = keys.reduce(0.0) { $0 + Double(elig($1).need) }
        return need > 0 ? min(1, have / need) : 0
    }
    private var shotsRemaining: Int {
        ["s_perf", "a_acc", "c_cons", "p_power"].reduce(0) { $0 + max(elig($1).need - elig($1).have, 0) }
    }

    private func scoreBuildingTab(_ s: ScoreResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            buildingOverviewCard(s)
            buildingTrendCard
            provisionalNote
            buildingPartsSection(s)
        }
    }

    private func buildingOverviewCard(_ s: ScoreResponse) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image("ScoreBadgePlatinum").resizable().scaledToFit().frame(width: 96, height: 96)
                .grayscale(1).blur(radius: 4).opacity(0.5)
                .overlay(Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(LS.textSecondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("LANESIGHT SCORE").font(.system(size: 8, weight: .semibold)).tracking(0.2).foregroundStyle(LS.action)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("—").font(.system(size: 44, weight: .bold)).foregroundStyle(LS.textFaint)
                    Text("BUILDING").font(.system(size: 13, weight: .bold)).tracking(0.5).foregroundStyle(LS.textSecondary)
                }
                Text(shotsRemaining > 0 ? "\(shotsRemaining) more measured shots to unlock your score"
                                        : "Finishing up your first score…")
                    .font(.system(size: 11)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Score unlocks").font(.system(size: 10)).foregroundStyle(LS.textSecondary)
                        Spacer()
                        Text("\(Int((unlockPct * 100).rounded()))%").font(.system(size: 11, weight: .bold)).foregroundStyle(LS.textPrimary)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(LS.track).frame(height: 8)
                        GeometryReader { g in Capsule().fill(LS.action).frame(width: max(0, g.size.width * CGFloat(unlockPct)), height: 8) }
                            .frame(height: 8)
                    }
                    .frame(height: 8)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private var buildingTrendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score trend").font(.system(size: 17, weight: .bold)).foregroundStyle(LS.textPrimary)
            RoundedRectangle(cornerRadius: 8).fill(LS.track).frame(height: 44)
                .overlay(Text("Your trend starts with your first score")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        .opacity(0.65)
    }

    private func buildingPartsSection(_ s: ScoreResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score parts").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("How it's calculated").font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
            }
            Text("Each part needs enough measured shots before it counts. Inputs read “—” until the part is ready.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
            buildingPartCard("Performance", 40, "s_perf", s.s_perf, performanceRows)
            buildingPartCard("Accuracy", 25, "a_acc", s.a_acc, accuracyRows)
            buildingPartCard("Consistency", 25, "c_cons", s.c_cons, consistencyRows)
            buildingPartCard("Power", 10, "p_power", s.p_power, powerRows)
        }
    }

    /// A part card in building mode: shot-progress bar + have/need; a ready part shows its value + "Ready ✓".
    /// Input rows read "—" while building, except a coverage row (e.g. "Shots with a target set") which is real.
    private func buildingPartCard(_ title: String, _ weight: Int, _ key: String, _ value: Double?, _ rows: [PartRow]) -> some View {
        let e = elig(key)
        let frac = e.need > 0 ? min(1, Double(e.have) / Double(e.need)) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                (Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(LS.textPrimary)
                 + Text("  ·  \(weight)%").font(.system(size: 13, weight: .medium)).foregroundStyle(LS.textSecondary))
                Spacer()
                if e.met, let v = value {
                    HStack(spacing: 6) {
                        Text(String(Int(v.rounded()))).font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                        Text("Ready ✓").font(.system(size: 11, weight: .bold)).foregroundStyle(LS.positive)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(LS.positive.opacity(0.14), in: Capsule())
                    }
                } else {
                    Text("\(e.have)/\(e.need)").font(.system(size: 18, weight: .bold).monospacedDigit()).foregroundStyle(LS.textFaint)
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(LS.track).frame(height: 6)
                GeometryReader { g in Capsule().fill(e.met ? LS.positive : LS.action)
                    .frame(width: max(0, g.size.width * CGFloat(e.met ? 1 : frac)), height: 6) }
                    .frame(height: 6)
            }
            .frame(height: 6)
            ForEach(rows) { r in
                let showReal = r.label.hasPrefix("Shots with a target set")
                HStack {
                    Text(r.label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    Spacer()
                    Text(showReal ? r.value : "—")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private var scoredHistory: [Double] { history.compactMap { $0.eligible == true ? $0.score : nil } }
    private var overallDelta: Double? {
        guard let f = scoredHistory.first, let l = scoredHistory.last, scoredHistory.count >= 2 else { return nil }
        return l - f
    }

    private func scoreTrendCard(_ s: ScoreResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Score trend").font(.system(size: 17, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.intStr(s.score)).font(.system(size: 28, weight: .bold)).foregroundStyle(LS.textPrimary)
                    deltaLabel(overallDelta)
                    Text("90 days").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                }
            }
            if scoredHistory.count >= 2 {
                Sparkline(values: scoredHistory, color: LS.dataPurple).frame(height: 44)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    @ViewBuilder private func deltaLabel(_ d: Double?) -> some View {
        if let d {
            Label("\(d >= 0 ? "+" : "")\(Int(d.rounded()))", systemImage: d >= 0 ? "arrow.up" : "arrow.down")
                .font(.system(size: 13, weight: .bold)).labelStyle(.titleAndIcon)
                .foregroundStyle(d >= 0 ? LS.positive : LS.bestEffort)
        }
    }

    private var provisionalNote: some View {
        let best = scoredHistory.max()
        return Text("Provisional · personal index, not a ranking." + (best.map { " Best \(Int($0.rounded()))." } ?? ""))
            .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private struct PartRow: Identifiable { let id = UUID(); let label: String; let value: String }

    private func scorePartsSection(_ s: ScoreResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Score parts").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("How it's calculated").font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
            }
            Text("Provisional formula (DEC-077). Weighted parts; a part with too few measured shots reads “—”.")
                .font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
            partCard("Performance", weight: 40, value: s.s_perf, delta: partDelta(\.s_perf), rows: performanceRows)
            partCard("Accuracy", weight: 25, value: s.a_acc, delta: partDelta(\.a_acc), rows: accuracyRows)
            partCard("Consistency", weight: 25, value: s.c_cons, delta: partDelta(\.c_cons), rows: consistencyRows)
            partCard("Power", weight: 10, value: s.p_power, delta: partDelta(\.p_power), rows: powerRows)
        }
    }

    private func partDelta(_ kp: KeyPath<ScoreResponse, Double?>) -> Double? {
        let vals = history.filter { $0.eligible == true }.compactMap { $0[keyPath: kp] }
        guard let f = vals.first, let l = vals.last, vals.count >= 2 else { return nil }
        return l - f
    }

    private func partCard(_ title: String, weight: Int, value: Double?, delta: Double?, rows: [PartRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                (Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(LS.textPrimary)
                 + Text("  ·  \(weight)%").font(.system(size: 13, weight: .medium)).foregroundStyle(LS.textSecondary))
                Spacer()
                HStack(spacing: 6) {
                    Text(value.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(value == nil ? LS.textFaint : LS.textPrimary)
                    if let d = delta {
                        Label("\(d >= 0 ? "" : "")\(Int(d.rounded()))", systemImage: d > 0 ? "arrow.up" : (d < 0 ? "arrow.down" : "minus"))
                            .font(.system(size: 12, weight: .bold)).labelStyle(.titleAndIcon)
                            .foregroundStyle(d > 0 ? LS.positive : (d < 0 ? LS.bestEffort : LS.textSecondary))
                    }
                }
            }
            ForEach(rows) { r in
                HStack {
                    Text(r.label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    Spacer()
                    Text(r.value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
    private func boards(_ v: Double?) -> String { v.map { "\(Fmt.number($0)) boards" } ?? "—" }

    private var performanceRows: [PartRow] {
        let p = breakdown?.performance
        return [PartRow(label: "Pocket % (entry board 16–19)", value: pct(p?.pocket_pct)),
                PartRow(label: "Entry angle in 4–6°", value: pct(p?.angle_pct))]
    }
    private var accuracyRows: [PartRow] {
        let a = breakdown?.accuracy
        let cov = (a?.n_with_target).map { "\($0) of \(a?.n_total ?? 0)" } ?? "—"
        return [PartRow(label: "Avg miss at arrows", value: boards(a?.avg_arrow_miss)),
                PartRow(label: "Avg miss at breakpoint", value: boards(a?.avg_bp_miss)),
                PartRow(label: "Shots with a target set", value: cov)]
    }
    private var consistencyRows: [PartRow] {
        let sp = breakdown?.consistency?.spreads
        func spread(_ k: String, _ unit: String) -> String { sp?[k].map { "\(Fmt.number($0)) \(unit)" } ?? "—" }
        return [PartRow(label: "Speed spread", value: spread("ball_speed", "mph")),
                PartRow(label: "Arrows spread", value: spread("arrows", "boards")),
                PartRow(label: "Breakpoint spread", value: spread("breakpoint", "boards"))]
    }
    private var powerRows: [PartRow] {
        let p = breakdown?.power
        let weight = model.currentBall?.weight_lb.map { "\(Int($0.rounded())) lb" } ?? "—"
        return [PartRow(label: "Entry speed", value: p?.entry_speed.map { "\(Fmt.number($0)) mph" } ?? "—"),
                PartRow(label: "Rev rate", value: p?.rev_rate.map { "\(Int($0.rounded())) rpm" } ?? "—"),
                PartRow(label: "Entry angle", value: p?.entry_angle.map { String(format: "%.1f°", $0) } ?? "—"),
                PartRow(label: "Ball weight", value: weight)]
    }

    // v3.7 Arsenal tab (DEC-085, Figma 431:5748): per-ball and per-oil-pattern rollups from /me/stats/equipment.
    // A new bowler sees the real ball + pattern they've used so far, with a small-sample note (not an empty card).
    private var equipmentTab: some View {
        LoadableView(state: equipment, retry: { Task { await loadEquipment() } }) { e in
            let balls = e.by_ball ?? []
            let patterns = e.by_pattern ?? []
            if balls.isEmpty && patterns.isEmpty {
                emptyCard("Arsenal stats",
                          "Per-ball and per-pattern rollups appear once you log measured shots. Tag a ball when you record and it rolls up here.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    let n = (balls.map { $0.n ?? 0 }.max() ?? 0)
                    if n > 0 && n < 20 { smallSampleBanner(n) }
                    if !balls.isEmpty { equipGroupCard("By ball", "Ball", balls) }
                    if !patterns.isEmpty { equipGroupCard("By oil pattern", "Pattern", patterns) }
                    Text("Expected reaction comes from your ball + layout; measured shots refine it. Groups with fewer than 20 shots are a small sample.")
                        .font(.system(size: 11)).foregroundStyle(LS.textFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Yellow small-sample note (DEC-085): a new bowler sees real values from their first shots, clearly flagged.
    private func smallSampleBanner(_ n: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(LS.dataYellow)
            Text("Based on \(n) shot\(n == 1 ? "" : "s") from your first session\(n == 1 ? "" : "s"). Early numbers move around until you have ~20.")
                .font(.system(size: 12)).foregroundStyle(LS.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.dataYellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.dataYellow.opacity(0.5), lineWidth: 1))
    }

    private func equipGroupCard(_ title: String, _ colHeader: String, _ rows: [EquipGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            HStack {
                Text(colHeader).font(.system(size: 10, weight: .semibold)).foregroundStyle(LS.textSecondary)
                Spacer()
                Text("shots · mph · rev · pocket").font(.system(size: 10, weight: .semibold)).foregroundStyle(LS.textSecondary)
            }
            ForEach(rows) { g in
                HStack(alignment: .firstTextBaseline) {
                    Text(g.name ?? "—").font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(equipLine(g)).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                }
                if g.identity != rows.last?.identity { Divider().overlay(LS.border) }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func equipLine(_ g: EquipGroup) -> String {
        [ "\(g.n ?? 0)",
          g.speed.map { Fmt.number($0) } ?? "—",
          g.rev.map { "\(Int($0.rounded()))" } ?? "—",
          g.pocket_pct.map { "\(Int($0.rounded()))%" } ?? "—",
        ].joined(separator: " · ")
    }

    private func loadEquipment() async {
        equipment = .loading
        do { equipment = .loaded(try await model.makeClient().equipmentStats()) }
        catch { equipment = .failed(error.localizedDescription) }
    }

    // MARK: Throw

    // v3.7 Shot tab (Figma 427:5614): a 3×3 grid of metric rings (each taps through to its detail), a
    // guidance note, and the metric-coverage card. Ring values are live — measured means from /me/stats
    // plus pocket %/accuracy from the score breakdown; a metric without data shows "—".
    private struct RingSpec {
        let metric: String; let title: String; let unit: String; let lo: Double; let hi: Double; let color: Color
        let value: Double?
    }
    private func shotRings(_ s: StatsResponse) -> [RingSpec] {
        func avg(_ k: String) -> Double? { s.averages?[k]?.mean }
        return [
            RingSpec(metric: "ball_speed", title: "Speed", unit: "mph", lo: 8, hi: 24, color: LS.action, value: avg("ball_speed")),
            RingSpec(metric: "rev_rate", title: "Rev Rate", unit: "rpm", lo: 100, hi: 600, color: LS.dataPurple, value: avg("rev_rate")),
            RingSpec(metric: "accuracy", title: "Accuracy", unit: "", lo: 0, hi: 100, color: LS.action, value: breakdown?.accuracy?.value),
            RingSpec(metric: "pocket", title: "Pocket", unit: "%", lo: 0, hi: 100, color: LS.dataPurple, value: breakdown?.performance?.pocket_pct),
            RingSpec(metric: "strike", title: "Strike %", unit: "%", lo: 0, hi: 100, color: LS.success, value: nil),
            RingSpec(metric: "entry_angle", title: "Entry", unit: "°", lo: 2, hi: 8, color: LS.action, value: avg("entry_angle")),
            RingSpec(metric: "breakpoint_distance", title: "Breakpoint", unit: "ft", lo: 30, hi: 55, color: LS.dataOrange, value: avg("breakpoint_distance")),
            RingSpec(metric: "loft", title: "Loft", unit: "ft", lo: 0, hi: 5, color: LS.dataYellow, value: avg("loft")),
            RingSpec(metric: "impact_energy", title: "Impact", unit: "J", lo: 0, hi: 300, color: LS.dataPurple, value: avg("impact_energy")),
        ]
    }

    private var throwTab: some View {
        LoadableView(state: throwStats, retry: { Task { await loadThrow() } }) { s in
            if s.empty == true || (s.n_shots ?? 0) == 0 {
                emptyCard("Shot stats need more shots",
                          "Record shots and they'll roll up here — speed, rev rate, entry, breakpoint, loft and more, each with its own trend and breakdown by ball and pattern.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(shotRings(s), id: \.metric) { r in
                            NavigationLink { MetricDetailView(metric: r.metric) } label: {
                                let vstr = r.value.map { String(format: $0 >= 100 ? "%.0f" : ($0 == $0.rounded() ? "%.0f" : "%.1f"), $0) } ?? "—"
                                MetricRing(label: r.title, value: vstr, unit: r.value == nil ? "" : r.unit,
                                           fraction: r.value.map { ($0 - r.lo) / (r.hi - r.lo) } ?? 0, color: r.color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Tap any metric for its average, range, trend and breakdown by ball and pattern. Impact Energy is energy at entry, not a carry prediction.")
                        .font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
                    coverageCard(s)
                    // DEC-085: a new bowler sees real values from the first shots, flagged as a small sample.
                    if let n = s.n_shots, n > 0 && n < 20 { smallSampleBanner(n) } else { sampleNote(s) }
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
                        .font(.lsCaption).foregroundStyle(LS.textFaint)
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
                    Text(MetricDisplay.humanize(key)).font(.lsCaption2).foregroundStyle(LS.textSecondary).lineLimit(1)
                    if let mean = avg?.mean {
                        Text(Fmt.number(mean)).font(.lsTitle3.weight(.heavy).monospacedDigit()).foregroundStyle(LS.textPrimary)
                        Text(units[key] ?? "avg").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                    } else {
                        Text("—").font(.lsTitle3.weight(.heavy)).foregroundStyle(LS.textFaint)
                        Text("no measured shots").font(.lsCaption2).foregroundStyle(LS.textFaint)
                    }
                    if let pct = cov?.pct { Text("\(Int(pct))% measured").font(.lsCaption2).foregroundStyle(coverageColor(pct)) }
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
                Text("% of shots measured").font(.lsCaption2).foregroundStyle(LS.textSecondary)
            }
            ForEach(rows, id: \.key) { key, cov in
                HStack(spacing: 10) {
                    Text(MetricDisplay.humanize(key)).font(.lsCaption).foregroundStyle(LS.textPrimary)
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
                        .font(.lsCaption.monospacedDigit()).foregroundStyle(LS.textSecondary)
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
                            Text(MetricDisplay.humanize(r.metric ?? "")).font(.lsSubheadline).foregroundStyle(LS.textPrimary)
                            Text(r.reason ?? "").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                        }
                        Spacer()
                        Text("\(r.count ?? 0)×").font(.lsCaption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                    }
                }
            }
            .lsCard()
        }
    }

    private func sampleNote(_ s: StatsResponse) -> some View {
        Text("Based on \(s.n_shots ?? 0) shot\((s.n_shots ?? 0) == 1 ? "" : "s") in range.")
            .font(.lsCaption2).foregroundStyle(LS.textFaint)
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "hourglass").font(.lsHeadline).foregroundStyle(LS.textPrimary)
            Text(message).font(.lsCallout).foregroundStyle(LS.textSecondary)
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
        if tab == 0 { await loadThrow() }
        else if tab == 1 { await loadForm() }
        else if tab == 3 { await loadEquipment() }      // Arsenal; Score (tab 2) loads via loadScore() in .task
    }

    private func loadScore() async {
        score = .loading
        do {
            let client = try model.makeClient()
            async let s = client.score()
            async let h = client.scoreHistory()
            async let b = try? client.scoreBreakdown()      // nil until the endpoint is deployed → rows show "—"
            let (sv, hv) = try await (s, h)
            history = hv
            breakdown = await b
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

/// A compact score sparkline (filled area + line) for the Stats trend card. Scales to its values' range.
struct Sparkline: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count >= 2 {
                    area(pts, height: geo.size.height)
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    line(pts).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 1)
        let dx = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * dx, y: size.height * (1 - CGFloat((v - lo) / span)) * 0.9 + size.height * 0.05)
        }
    }
    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path(); p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }; return p
    }
    private func area(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = line(pts)
        p.addLine(to: CGPoint(x: pts.last!.x, y: height))
        p.addLine(to: CGPoint(x: pts.first!.x, y: height))
        p.closeSubpath()
        return p
    }
}
