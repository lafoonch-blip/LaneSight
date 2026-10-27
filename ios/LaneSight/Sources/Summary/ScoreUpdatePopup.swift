import SwiftUI

/// Session score-update popup (v3.7 Figma 424:5313) — shown on End and re-openable from the summary.
/// The new LaneSight Score + its change, the four part scores with their deltas, and this session's core
/// metrics vs the bowler's average. All live: GET /me/score + /me/score/history + /sessions/{id}/summary.
/// Deltas / "vs average" show only when there's history / typical data; never fabricated.
struct ScoreUpdatePopup: View {
    @EnvironmentObject var model: AppModel
    var sessionId: String?
    var onSeeSummary: () -> Void = {}
    var onClose: () -> Void = {}

    @State private var score: ScoreResponse?
    @State private var history: [ScoreResponse] = []
    @State private var summary: SessionSummary?

    // DEC-038 tier bands (lower, upper, next-tier name) — matches the Home/Stats progress.
    private static let bands: [(lo: Double, hi: Double, next: String)] = [
        (0, 400, "Silver"), (400, 550, "Gold"), (550, 700, "Platinum"), (700, 850, "Onyx"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose() }
            ScrollView {
                VStack(spacing: 12) {
                    Text("SESSION COMPLETE").font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(LS.link)
                    Image("ScoreBadgePlatinum").resizable().scaledToFit().frame(width: 96, height: 96)
                    if let s = score, let v = s.score {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Int(v.rounded()))").font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                            if let d = totalDelta {
                                Label("\(Int(d.rounded()))", systemImage: d >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 15, weight: .bold)).labelStyle(.titleAndIcon)
                                    .foregroundStyle(d >= 0 ? LS.positive : LS.bestEffort)
                            }
                        }
                        Text(tierLine(v)).font(.system(size: 13, weight: .medium)).foregroundStyle(LS.textSecondary)
                        progressBar(v)
                        scorePartsCard(s)
                    } else {
                        Text("Building your score").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        Text("Each part needs enough measured shots before a score appears.")
                            .font(.system(size: 12)).foregroundStyle(LS.textSecondary).multilineTextAlignment(.center)
                    }
                    coreMetricsCard
                    Button("See session summary") { onSeeSummary() }.buttonStyle(PrimaryButtonStyle())
                    Text("Closes on its own after a few seconds").font(.system(size: 11)).foregroundStyle(LS.textFaint)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(LS.bg, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                .padding(.horizontal, 18)
            }
        }
        .task { await load() }
    }

    // MARK: score helpers

    private var scored: [Double] { history.compactMap { $0.eligible == true ? $0.score : nil } }
    private var totalDelta: Double? {
        guard let f = scored.first, let l = scored.last, scored.count >= 2 else { return nil }
        return l - f
    }
    private func partDelta(_ kp: KeyPath<ScoreResponse, Double?>) -> Double? {
        let v = history.filter { $0.eligible == true }.compactMap { $0[keyPath: kp] }
        guard let f = v.first, let l = v.last, v.count >= 2 else { return nil }
        return l - f
    }
    private func tierLine(_ s: Double) -> String {
        guard let b = Self.bands.first(where: { s < $0.hi }) else { return (score?.tier ?? "").capitalized }
        return "\((score?.tier ?? "").uppercased()) · \(Int((b.hi - s).rounded())) points to \(b.next)"
    }
    private func progressBar(_ s: Double) -> some View {
        let b = Self.bands.first { s < $0.hi }
        let pct = b.map { min(1, max(0, (s - $0.lo) / ($0.hi - $0.lo))) } ?? 1
        return ZStack(alignment: .leading) {
            Capsule().fill(LS.track).frame(height: 6)
            GeometryReader { g in Capsule().fill(LS.action).frame(width: g.size.width * pct, height: 6) }.frame(height: 6)
        }
        .frame(height: 6).frame(maxWidth: 240)
    }

    private func scorePartsCard(_ s: ScoreResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCORE PARTS").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            partRow("Performance", s.s_perf, partDelta(\.s_perf))
            partRow("Accuracy", s.a_acc, partDelta(\.a_acc))
            partRow("Consistency", s.c_cons, partDelta(\.c_cons))
            partRow("Power", s.p_power, partDelta(\.p_power))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.border, lineWidth: 1))
    }

    private func partRow(_ label: String, _ value: Double?, _ delta: Double?) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
            Spacer()
            Text(value.map { String(Int($0.rounded())) } ?? "—")
                .font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(LS.textPrimary)
            deltaBadge(delta)
        }
    }

    private var coreMetricsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CORE METRICS VS YOUR AVERAGE").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            metricRow("Speed", "ball_speed", "mph")
            metricRow("Rev rate", "rev_rate", "rpm")
            metricRow("Entry angle", "entry_angle", "°")
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.border, lineWidth: 1))
    }

    @ViewBuilder private func metricRow(_ label: String, _ key: String, _ unit: String) -> some View {
        if let now = summary?.mean(key) {
            let typ = summary?.typical?.metrics?[key]
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                Spacer()
                Text("\(Fmt.number(now)) \(unit)").font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                deltaBadge(typ.map { now - $0 })
            }
        }
    }

    @ViewBuilder private func deltaBadge(_ d: Double?) -> some View {
        if let d {
            Label("\(Fmt.number(abs(d)))", systemImage: d > 0 ? "arrow.up" : (d < 0 ? "arrow.down" : "minus"))
                .font(.system(size: 11, weight: .bold)).labelStyle(.titleAndIcon)
                .foregroundStyle(d > 0 ? LS.positive : (d < 0 ? LS.bestEffort : LS.textSecondary))
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func load() async {
        guard let client = try? model.makeClient() else { return }
        async let sc = try? client.score()
        async let h = try? client.scoreHistory()
        score = await sc
        history = (await h) ?? []
        if let sid = sessionId { summary = try? await client.sessionSummary(sid) }
    }
}
