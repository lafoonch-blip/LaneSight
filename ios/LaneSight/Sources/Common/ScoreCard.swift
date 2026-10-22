import SwiftUI

/// The LaneSight Score card (Main / Stats / Summary). Shows the score + tier when eligible, or an
/// honest "Building your score" state with per-part eligibility progress when not. All values are
/// from GET /me/score; deltas/best are derived from GET /me/score/history when available.
struct ScoreCard: View {
    let score: ScoreResponse
    var history: [ScoreResponse] = []
    var showBreakdown = true

    private struct Part { let name: String; let desc: String; let value: Double? }

    private var parts: [Part] {
        [
            Part(name: "Performance", desc: "pocket", value: score.s_perf),
            Part(name: "Accuracy", desc: "to target", value: score.a_acc),
            Part(name: "Consistency", desc: "repeat", value: score.c_cons),
            Part(name: "Power", desc: "ball data", value: score.p_power),
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
                Text("BETA").font(.caption2.bold()).foregroundStyle(LS.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LS.cyan.opacity(0.15), in: Capsule())
                Spacer()
            }

            if score.eligible == true, let value = score.score {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(String(Int(value.rounded())))
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(LS.textPrimary)
                        .accessibilityLabel("LaneSight score \(Int(value.rounded()))")
                    VStack(alignment: .leading, spacing: 2) {
                        if let tier = score.tier {
                            Text(tier.uppercased()).font(.subheadline.bold()).foregroundStyle(LS.cyan)
                        }
                        if let d = delta {
                            Label("\(d >= 0 ? "+" : "")\(Int(d.rounded())) over range",
                                  systemImage: d >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.caption).foregroundStyle(d >= 0 ? LS.measured : LS.bestEffort)
                        }
                        if let b = best {
                            Text("Best \(Int(b.rounded()))").font(.caption2).foregroundStyle(LS.textSecondary)
                        }
                    }
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Building your score", systemImage: "hourglass")
                        .font(.headline).foregroundStyle(LS.textPrimary)
                    Text("Each part needs enough measured shots before a score appears.")
                        .font(.caption).foregroundStyle(LS.textSecondary)
                    eligibilityRows
                }
            }

            if showBreakdown {
                Divider().overlay(LS.cardStroke)
                Text("SCORE BREAKDOWN").lsEyebrow()
                ForEach(parts, id: \.name) { part in
                    HStack {
                        Text(Fmt.part(part.value))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(part.value == nil ? LS.textFaint : LS.textPrimary)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.name).font(.subheadline).foregroundStyle(LS.textPrimary)
                            Text(part.desc).font(.caption2).foregroundStyle(LS.textSecondary)
                        }
                        Spacer()
                        if part.value == nil {
                            Text("building").font(.caption2).foregroundStyle(LS.textFaint)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(part.name) \(part.value == nil ? "building" : Fmt.part(part.value))")
                }
                if let fv = score.formula_version {
                    Text(fv).font(.caption2).foregroundStyle(LS.textFaint)
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
                                .font(.caption)
                            Text(MetricDisplay.humanize(key)).font(.caption).foregroundStyle(LS.textSecondary)
                            Spacer()
                            Text("\(e.have ?? 0)/\(e.need ?? 0)")
                                .font(.caption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
