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

    private var isBuilding: Bool { !(score.eligible == true && score.score != nil) }

    private var overviewCard: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(badgeName(score.tier)).resizable().scaledToFit()
                .frame(width: isBuilding ? 120 : 150, height: isBuilding ? 120 : 150)
                // DEC-083 building: the tier badge is greyed + slightly blurred, with a lock, no tier name.
                .grayscale(isBuilding ? 1 : 0)
                .blur(radius: isBuilding ? 4 : 0)
                .opacity(isBuilding ? 0.55 : 1)
                .overlay { if isBuilding { Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(LS.textSecondary) } }
                .accessibilityLabel(isBuilding ? "Score building" : "\(score.tier ?? "") tier badge")
            if let value = score.score, !isBuilding {
                scoreDetails(value: value)
            } else {
                buildingDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isBuilding ? 12 : 10)
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

    private struct Part { let name: String; let value: Double?; let icon: String; let color: Color; let weight: Int; let key: String }
    private var parts: [Part] {
        [
            Part(name: "Performance", value: score.s_perf, icon: "IconPerformance", color: LS.dataPurple, weight: 40, key: "s_perf"),
            Part(name: "Accuracy", value: score.a_acc, icon: "IconAccuracy", color: LS.action, weight: 25, key: "a_acc"),
            Part(name: "Consistency", value: score.c_cons, icon: "IconConsistency", color: LS.success, weight: 25, key: "c_cons"),
            Part(name: "Power", value: score.p_power, icon: "IconPower", color: LS.dataYellow, weight: 10, key: "p_power"),
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

    /// DEC-083 per-tile 30-day change: "▲ 2 · 30 days" / "▼ 2 · 30 days" / "– · 30 days", or "New" when the
    /// server has no 30-day-old reference for this part yet. Never a fabricated number.
    @ViewBuilder private func partChangeLabel(_ key: String) -> some View {
        if let d = score.parts_delta_30d?[key] {
            let n = Int(d.rounded())
            let arrow = n > 0 ? "▲" : (n < 0 ? "▼" : "–")
            let color = n > 0 ? LS.positive : (n < 0 ? LS.bestEffort : LS.textSecondary)
            Text(n == 0 ? "– · 30 days" : "\(arrow) \(abs(n)) · 30 days")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
        } else {
            Text("New").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.textSecondary)
        }
    }

    private func metricCard(_ p: Part) -> some View {
        // DEC-083: a part is shown as "ready" (its score) once its own floor is met, even while the overall
        // score is still building; a not-ready part is dimmed and shows its shot progress instead.
        let e = partElig(p.key)
        let ready = e.met || score.eligible == true
        let frac = e.need > 0 ? min(1, Double(e.have) / Double(e.need)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(p.color.opacity(0.22)).frame(width: 26, height: 26)
                    Image(p.icon).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(p.color)
                }
                Text(ready && p.value != nil ? String(Int(p.value!.rounded())) : "—")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(ready && p.value != nil ? LS.textPrimary : LS.textFaint)
            }
            Text(p.name)
                .font(.system(size: 11, weight: .medium)).tracking(-0.1).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 11)
            if ready {
                ZStack(alignment: .leading) {
                    Capsule().fill(LS.track).frame(height: 5)
                    GeometryReader { g in
                        Capsule().fill(p.color).frame(width: max(0, g.size.width * CGFloat((p.value ?? 0) / 100)), height: 5)
                    }
                    .frame(height: 5)
                }
                .frame(height: 5).padding(.top, 10)
                // Live score → the part's 30-day change (DEC-083); still building → "Ready ✓".
                if score.eligible == true {
                    partChangeLabel(p.key).lineLimit(1).padding(.top, 4)
                } else {
                    Text("Ready ✓").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LS.positive).lineLimit(1).padding(.top, 4)
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule().fill(LS.track).frame(height: 5)
                    GeometryReader { g in
                        Capsule().fill(p.color.opacity(0.7)).frame(width: max(0, g.size.width * CGFloat(frac)), height: 5)
                    }
                    .frame(height: 5)
                }
                .frame(height: 5).padding(.top, 10)
                Text("\(e.have)/\(e.need) shots")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(LS.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75).padding(.top, 4)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LS.border, lineWidth: 1))
        .opacity(ready ? 1 : 0.6)       // DEC-083: a not-ready part is dimmed
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.name) \(ready && p.value != nil ? String(Int(p.value!.rounded())) + " of 100" : "building, \(e.have) of \(e.need) shots")")
    }

    // MARK: Building state (DEC-083 Option A — the real score card, locked until every part is ready)

    /// have/need/met for a part from the live eligibility (never mock counts).
    private func partElig(_ key: String) -> (have: Int, need: Int, met: Bool) {
        let e = score.eligibility?[key]
        return (e?.have ?? 0, e?.need ?? 0, e?.met ?? false)
    }
    private static let partKeys = ["s_perf", "a_acc", "c_cons", "p_power"]
    /// Overall unlock fraction = measured shots so far / shots required, summed across the four parts.
    private var unlockPct: Double {
        let have = Self.partKeys.reduce(0.0) { $0 + Double(min(partElig($1).have, partElig($1).need)) }
        let need = Self.partKeys.reduce(0.0) { $0 + Double(partElig($1).need) }
        return need > 0 ? min(1, have / need) : 0
    }
    /// DEC-083 hint: the largest number of shots any part still needs; if that part is Accuracy, say to set a target.
    private var buildingHint: String {
        let gaps = Self.partKeys.map { (key: $0, gap: max(partElig($0).need - partElig($0).have, 0)) }
        guard let worst = gaps.max(by: { $0.gap < $1.gap }), worst.gap > 0 else { return "Finishing up your first score…" }
        let target = worst.key == "a_acc" ? ", with a target set" : ""
        return "About \(worst.gap) more shot\(worst.gap == 1 ? "" : "s")\(target)"
    }

    private var buildingDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("LANESIGHT SCORE").font(.system(size: 8, weight: .semibold)).tracking(0.2).foregroundStyle(LS.action)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text("How it works").font(.system(size: 8, weight: .semibold))
                    Text("›").font(.system(size: 11))
                }
                .foregroundStyle(LS.textPrimary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(LS.borderStrong, lineWidth: 1))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("—").font(.system(size: 44, weight: .bold)).foregroundStyle(LS.textFaint)
                Text("BUILDING").font(.system(size: 14, weight: .bold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            }
            .padding(.top, 2)
            Text(buildingHint).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            unlockBar.padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Score unlocks · N%" bar — replaces the next-tier progress bar while building (DEC-083).
    private var unlockBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Score unlocks").font(.system(size: 9)).foregroundStyle(LS.textSecondary)
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
