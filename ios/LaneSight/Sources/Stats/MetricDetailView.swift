import SwiftUI

/// A Stats metric-detail screen (v3.7 Figma 454:6949 "Speed detail" + the 8 siblings). One metric's
/// average ± spread + range, a by-session trend, and by-ball / by-oil-pattern breakdowns — all from
/// GET /me/stats/metric/{metric}. A metric with too few measured shots shows an honest building state;
/// unmeasured values are "—", never fabricated.
struct MetricDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let metric: String

    @State private var detail: Loadable<MetricDetailResponse> = .idle

    struct Meta { let title: String; let unit: String; let basis: String }
    static let meta: [String: Meta] = [
        "ball_speed": .init(title: "Speed", unit: "mph", basis: "60 ft average"),
        "rev_rate": .init(title: "Rev rate", unit: "rpm", basis: "at release"),
        "entry_angle": .init(title: "Entry angle", unit: "°", basis: "at the pocket"),
        "entry_board": .init(title: "Entry board", unit: "board", basis: "at the pocket"),
        "breakpoint_board": .init(title: "Breakpoint", unit: "board", basis: "at the breakpoint"),
        "breakpoint_distance": .init(title: "Breakpoint distance", unit: "ft", basis: "down the lane"),
        "arrows_board": .init(title: "Arrows", unit: "board", basis: "at 15 ft"),
        "loft": .init(title: "Loft", unit: "ft", basis: "past the foul line"),
        "impact_energy": .init(title: "Impact", unit: "J", basis: "energy at entry, not a carry prediction"),
    ]
    private var m: Meta { Self.meta[metric] ?? Meta(title: MetricDisplay.humanize(metric), unit: "", basis: "") }

    var body: some View {
        VStack(spacing: 0) {
            LSTabHeader(title: "Stats")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filterChips
                    Button { dismiss() } label: {
                        Label("Shot stats", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.link)
                    }
                    Text(m.title).font(.system(size: 28, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text("\(m.basis) · last 90 days · all balls, all patterns")
                        .font(.system(size: 13)).foregroundStyle(LS.textSecondary)

                    LoadableView(state: detail, retry: { Task { await load() } }) { d in
                        if d.status == "building" || (d.n ?? 0) == 0 {
                            buildingCard
                        } else {
                            summaryCard(d)
                            if (d.trend?.count ?? 0) >= 2 { trendCard(d) }
                            if let bb = d.by_ball, !bb.isEmpty { groupCard("By ball", bb) }
                            if let bp = d.by_pattern, !bp.isEmpty { groupCard("By oil pattern", bp) }
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(16)
            }
        }
        .background(LSBackground())
        .navigationBarHidden(true)
        .task { await load() }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(["Last 90 days", "All balls", "All patterns"], id: \.self) { label in
                HStack(spacing: 4) {
                    Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(LS.textPrimary)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(LS.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(LS.card, in: Capsule())
                .overlay(Capsule().strokeBorder(LS.border, lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return m.unit == "°" ? String(format: "%.1f", v) : Fmt.number(v)
    }

    private func summaryCard(_ d: MetricDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                statCol("AVERAGE", d.avg.map { "\(fmt($0)) \(m.unit)" } ?? "—")
                statCol("SPREAD", d.spread.map { "± \(fmt($0))" } ?? "—")
                if let r = d.range, r.count == 2 {
                    statCol("RANGE", "\(fmt(r[0]))–\(fmt(r[1]))")
                }
                Spacer(minLength: 0)
            }
            if let n = d.n, let cov = d.coverage {
                Text("\(n) shots measured of \(Int((Double(n) / max(cov, 0.0001)).rounded())) (\(Int((cov * 100).rounded()))%).")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func statCol(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.4).foregroundStyle(LS.textSecondary)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(LS.textPrimary)
        }
    }

    private func trendCard(_ d: MetricDetailResponse) -> some View {
        let means = (d.trend ?? []).compactMap { $0.mean }
        let delta = (means.count >= 2) ? (means.last! - means.first!) : nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("\(m.title) by session").font(.system(size: 17, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(means.last)).font(.system(size: 26, weight: .bold)).foregroundStyle(LS.textPrimary)
                    if let delta {
                        Label("\(delta >= 0 ? "" : "")\(fmt(abs(delta)))", systemImage: delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .bold)).labelStyle(.titleAndIcon)
                            .foregroundStyle(delta >= 0 ? LS.positive : LS.bestEffort)
                    }
                    Text("\(m.unit) avg").font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                }
            }
            Sparkline(values: means, color: LS.action).frame(height: 44)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func groupCard(_ title: String, _ rows: [MetricGroupStat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            ForEach(rows) { r in
                HStack {
                    Text(r.key ?? "—").font(.system(size: 13, weight: .medium)).foregroundStyle(LS.textPrimary)
                    Spacer()
                    Text("\(fmt(r.mean)) \(m.unit)").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(LS.textPrimary)
                    Text("\(r.n ?? 0) shots").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private var buildingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Building", systemImage: "hourglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
            Text("\(m.title) needs more measured shots before its detail fills in.")
                .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func load() async {
        detail = .loading
        do { detail = .loaded(try await model.makeClient().metricDetail(metric)) }
        catch { detail = .failed(error.localizedDescription) }
    }
}
