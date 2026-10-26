import SwiftUI

/// The LaneSight Score card, rebuilt to the v3.7 Figma (Home › Score overview 405:3165 + Score breakdown
/// 405:3166). Two stacked cards: the overview (tier badge + score + delta + progress) and the 4-metric
/// breakdown. All values are from GET /me/score; an ineligible user gets an honest "building" state with
/// per-part progress. Sizes/colors are the exact design-standard tokens (Inter in the mock → SF Pro here).
struct ScoreCard: View {
    let score: ScoreResponse
    var history: [ScoreResponse] = []
    var showBreakdown = true

    private var scoredHistory: [Double] { history.compactMap { $0.eligible == true ? $0.score : nil } }
    private var best: Double? { scoredHistory.max() }
    private var delta: Double? {
        guard let first = scoredHistory.first, let last = scoredHistory.last, scoredHistory.count >= 2 else { return nil }
        return last - first
    }

    var body: some View {
        VStack(spacing: 10) {
            overviewCard
            if showBreakdown { breakdownCard }
        }
    }

    // MARK: Overview (badge + score + delta + progress)

    private var overviewCard: some View {
        Group {
            if score.eligible == true, let value = score.score {
                HStack(alignment: .center, spacing: 6) {
                    Image(badgeName(score.tier))
                        .resizable().scaledToFit()
                        .frame(width: 150, height: 150)
                        .accessibilityLabel("\(score.tier ?? "") tier badge")
                    scoreDetails(value: value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            } else {
                buildingState.padding(14)
            }
        }
        .homeCard()
    }

    private func scoreDetails(value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("LANESIGHT SCORE")
                    .font(.system(size: 8, weight: .semibold)).tracking(0.2)
                    .foregroundStyle(LS.action)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text("View Details").font(.system(size: 8, weight: .semibold))
                    Text("›").font(.system(size: 11))
                }
                .foregroundStyle(LS.textPrimary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(LS.borderStrong, lineWidth: 1))
            }
            Text(String(Int(value.rounded())))
                .font(.system(size: 44, weight: .bold)).foregroundStyle(LS.textPrimary)
                .padding(.top, 2)
                .accessibilityLabel("LaneSight score \(Int(value.rounded()))")
            Text((score.tier ?? "").uppercased())
                .font(.system(size: 20, weight: .bold)).foregroundStyle(LS.action)
                .padding(.top, 4)
            deltaRow.padding(.top, 9)
            progressRow.padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var deltaRow: some View {
        if let d = delta {
            (Text(Image(systemName: d >= 0 ? "arrow.up" : "arrow.down")).foregroundColor(d >= 0 ? LS.positive : LS.bestEffort)
             + Text(" \(d >= 0 ? "+" : "")\(Int(d.rounded())) ").foregroundColor(d >= 0 ? LS.positive : LS.bestEffort).bold()
             + Text("pts in 90 days · provisional").foregroundColor(LS.textPrimary))
                .font(.system(size: 11, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        } else if let b = best {
            Text("Best \(Int(b.rounded())) · provisional").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
        } else {
            Text("Provisional · Beta formula").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
        }
    }

    @ViewBuilder private var progressRow: some View {
        if let value = score.score, let (next, pct) = tierProgress(value) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progress to \(next)")
                    Spacer()
                    Text("\(Int(((1 - pct) * tierBand(value)).rounded())) points to \(next)")
                }
                .font(.system(size: 9)).foregroundStyle(LS.textSecondary)
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(LS.track).frame(height: 8)
                        GeometryReader { g in
                            Capsule().fill(LS.action).frame(width: max(0, g.size.width * CGFloat(pct)), height: 8)
                        }
                        .frame(height: 8)
                    }
                    .frame(height: 8)
                    Text("\(Int((pct * 100).rounded()))%")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(LS.textPrimary).fixedSize()
                }
            }
        }
    }

    // MARK: Breakdown (4 metric cards)

    private struct Part { let name: String; let value: Double?; let icon: String; let color: Color; let weight: Int }
    private var parts: [Part] {
        [
            Part(name: "Performance", value: score.s_perf, icon: "IconPerformance", color: LS.dataPurple, weight: 40),
            Part(name: "Accuracy", value: score.a_acc, icon: "IconAccuracy", color: LS.action, weight: 25),
            Part(name: "Consistency", value: score.c_cons, icon: "IconConsistency", color: LS.success, weight: 25),
            Part(name: "Power", value: score.p_power, icon: "IconPower", color: LS.dataYellow, weight: 10),
        ]
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCORE BREAKDOWN")
                    .font(.system(size: 13, weight: .bold)).tracking(0.5).foregroundStyle(LS.action)
                Spacer()
                HStack(spacing: 2) {
                    Text("How it's calculated").font(.system(size: 11, weight: .medium))
                    Text("›").font(.system(size: 13))
                }
                .foregroundStyle(LS.link)
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(parts, id: \.name) { metricCard($0) }
            }
        }
        .padding(11)
        .homeCard()
    }

    private func metricCard(_ p: Part) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(p.color.opacity(0.22)).frame(width: 26, height: 26)
                    Image(p.icon).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(p.color)
                }
                Text(p.value == nil ? "—" : String(Int(p.value!.rounded())))
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(p.value == nil ? LS.textFaint : LS.textPrimary)
            }
            Text(p.name)
                .font(.system(size: 11, weight: .medium)).tracking(-0.1).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 11)
            ZStack(alignment: .leading) {
                Capsule().fill(LS.track).frame(height: 5)
                GeometryReader { g in
                    Capsule().fill(p.color).frame(width: max(0, g.size.width * CGFloat((p.value ?? 0) / 100)), height: 5)
                }
                .frame(height: 5)
            }
            .frame(height: 5).padding(.top, 10)
            Text("\(p.weight)% of score")
                .font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75).padding(.top, 4)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name) \(p.value == nil ? "building" : String(Int(p.value!.rounded()))) of 100, \(p.weight) percent of score")
    }

    // MARK: Building state

    private var buildingState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LANESIGHT SCORE").font(.system(size: 8, weight: .semibold)).tracking(0.2).foregroundStyle(LS.action)
                Spacer()
            }
            Label("Building your score", systemImage: "hourglass")
                .font(.headline).foregroundStyle(LS.textPrimary)
            Text("Each part needs enough measured shots before a score appears.")
                .font(.system(size: 11)).foregroundStyle(LS.textSecondary)
            if let elig = score.eligibility, !elig.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(elig.sorted(by: { $0.key < $1.key }), id: \.key) { key, e in
                        HStack {
                            Image(systemName: e.met == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(e.met == true ? LS.success : LS.textFaint).font(.caption)
                            Text(MetricDisplay.humanize(key)).font(.caption).foregroundStyle(LS.textSecondary)
                            Spacer()
                            Text("\(e.have ?? 0)/\(e.need ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(LS.textSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: helpers

    private func badgeName(_ tier: String?) -> String {
        // Only Platinum art is bundled so far; other tiers fall back until their badges are exported.
        switch (tier ?? "").lowercased() {
        case "platinum": return "ScoreBadgePlatinum"
        default: return "ScoreBadgePlatinum"
        }
    }

    /// Next tier + progress toward it (DEC-038 bands). Onyx (top) returns nil.
    private func tierProgress(_ s: Double) -> (next: String, pct: Double)? {
        for b in Self.bands where s < b.hi {
            return (b.next, min(1, max(0, (s - b.lo) / (b.hi - b.lo))))
        }
        return nil
    }
    private func tierBand(_ s: Double) -> Double {
        for b in Self.bands where s < b.hi { return b.hi - b.lo }
        return 150
    }
    private static let bands: [(lo: Double, hi: Double, next: String)] = [
        (0, 400, "Silver"), (400, 550, "Gold"), (550, 700, "Platinum"), (700, 850, "Onyx"),
    ]
}

/// The Home content-card container: home/card fill + the brighter home/card-stroke + 12pt radius (v3.7).
private extension View {
    func homeCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }
}
