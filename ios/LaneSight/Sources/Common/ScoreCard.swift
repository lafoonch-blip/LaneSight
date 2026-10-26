import SwiftUI

/// The LaneSight Score card (Main / Stats / Summary). Shows the score + tier when eligible, or an
/// honest "Building your score" state with per-part eligibility progress when not. All values are
/// from GET /me/score; deltas/best are derived from GET /me/score/history when available.
struct ScoreCard: View {
    let score: ScoreResponse
    var history: [ScoreResponse] = []
    var showBreakdown = true

    private struct Part {
        let name: String; let value: Double?; let icon: String; let color: Color; let weight: Int
    }

    private var parts: [Part] {
        [   // DEC-048 weights; S/A/C/P are each 0–100 (shown raw here, not the ×10 headline-scale)
            Part(name: "Performance", value: score.s_perf, icon: "chart.bar.fill", color: LS.dataPurple, weight: 40),
            Part(name: "Accuracy", value: score.a_acc, icon: "scope", color: LS.action, weight: 25),
            Part(name: "Consistency", value: score.c_cons, icon: "arrow.triangle.2.circlepath", color: LS.success, weight: 25),
            Part(name: "Power", value: score.p_power, icon: "bolt.fill", color: LS.dataYellow, weight: 10),
        ]
    }

    private var scoredHistory: [Double] { history.compactMap { $0.eligible == true ? $0.score : nil } }
    private var best: Double? { scoredHistory.max() }
    private var delta: Double? {
        guard let first = scoredHistory.first, let last = scoredHistory.last, scoredHistory.count >= 2 else { return nil }
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LANESIGHT SCORE").lsEyebrow()
                Text("BETA").font(.lsCaption2.bold()).foregroundStyle(LS.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LS.cyan.opacity(0.15), in: Capsule())
                Spacer()
            }

            if score.eligible == true, let value = score.score {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(Int(value.rounded())))
                        .font(.lsRoboto(52, weight: .bold))
                        .foregroundStyle(LS.textPrimary)
                        .accessibilityLabel("LaneSight score \(Int(value.rounded()))")
                    VStack(alignment: .leading, spacing: 2) {
                        if let tier = score.tier {
                            Text(tier.uppercased()).font(.lsSubheadline.bold()).foregroundStyle(LS.cyan)
                        }
                        if let d = delta {
                            Label("\(d >= 0 ? "+" : "")\(Int(d.rounded())) over range",
                                  systemImage: d >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.lsCaption).foregroundStyle(d >= 0 ? LS.measured : LS.bestEffort)
                        }
                        if let b = best {
                            Text("Best \(Int(b.rounded()))").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                        }
                    }
                    Spacer()
                }
                if let (next, pct) = tierProgress(value) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Progress to \(next)").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                            Spacer()
                            Text("\(Int((pct * 100).rounded()))%").font(.lsCaption2.bold()).foregroundStyle(LS.textPrimary)
                        }
                        ZStack(alignment: .leading) {
                            Capsule().fill(LS.border).frame(height: 5)
                            GeometryReader { g in
                                Capsule().fill(LS.cyan).frame(width: max(0, g.size.width * CGFloat(pct)), height: 5)
                            }
                            .frame(height: 5)
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Progress to \(next), \(Int((pct * 100).rounded())) percent")
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Building your score", systemImage: "hourglass")
                        .font(.lsHeadline).foregroundStyle(LS.textPrimary)
                    Text("Each part needs enough measured shots before a score appears.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                    eligibilityRows
                }
            }

            if showBreakdown {
                Divider().overlay(LS.cardStroke)
                Text("SCORE BREAKDOWN").lsEyebrow()
                HStack(alignment: .top, spacing: 10) {
                    ForEach(parts, id: \.name) { part in
                        breakdownColumn(part)
                    }
                }
                if let fv = score.formula_version {
                    Text(fv).font(.lsCaption2).foregroundStyle(LS.textFaint)
                }
            }
        }
        .lsCard()
    }

    private var eligibilityRows: some View {
        Group {
            if let elig = score.eligibility, !elig.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(elig.sorted(by: { $0.key < $1.key }), id: \.key) { key, e in
                        HStack {
                            Image(systemName: e.met == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(e.met == true ? LS.measured : LS.textFaint)
                                .font(.lsCaption)
                            Text(MetricDisplay.humanize(key)).font(.lsCaption).foregroundStyle(LS.textSecondary)
                            Spacer()
                            Text("\(e.have ?? 0)/\(e.need ?? 0)")
                                .font(.lsCaption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func breakdownColumn(_ part: Part) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: part.icon).font(.lsCaption).foregroundStyle(part.color)
            Text(part.value == nil ? "—" : String(Int(part.value!.rounded())))
                .font(.lsTitle3.bold().monospacedDigit())
                .foregroundStyle(part.value == nil ? LS.textFaint : LS.textPrimary)
            Text(part.name).font(.lsCaption2).foregroundStyle(LS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text("\(part.weight)% of score").font(.lsCaption2).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            ZStack(alignment: .leading) {
                Capsule().fill(LS.border).frame(height: 3)
                GeometryReader { geo in
                    Capsule().fill(part.color)
                        .frame(width: max(0, geo.size.width * CGFloat((part.value ?? 0) / 100)), height: 3)
                }
                .frame(height: 3)
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(part.name) \(part.value == nil ? "building" : String(Int(part.value!.rounded()))) of 100, \(part.weight) percent of score")
    }

    /// Next tier + progress toward it, from the DEC-038 tier bands. Onyx (top) returns nil (no bar).
    private func tierProgress(_ score: Double) -> (next: String, pct: Double)? {
        let bands: [(lo: Double, hi: Double, next: String)] = [
            (0, 400, "Silver"), (400, 550, "Gold"), (550, 700, "Platinum"), (700, 850, "Onyx"),
        ]
        for b in bands where score < b.hi {
            return (b.next, min(1, max(0, (score - b.lo) / (b.hi - b.lo))))
        }
        return nil
    }
}
