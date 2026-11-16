import SwiftUI

/// Session summary (v3.7 Figma 419:4904) — the post-session recap, also opened from history. Pulls the
/// session aggregates (GET /sessions/{id}/summary: averages ± spread, consistency, typical, early-vs-late,
/// focus), the LaneSight Score (GET /me/score) and the shot list (GET /sessions/{id}/shots). Numbers that
/// need data the account doesn't have yet (per-shot targets → accuracy; multi-session typical) show honest
/// building / "—" states, never fabricated.
struct SessionSummaryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionId: String

    @State private var summary: SessionSummary?
    @State private var shots: [SessionShotRow] = []
    @State private var score: ScoreResponse?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let score { scoreRow(score) }
                takeawayCard
                vsTypicalCard
                sessionStats
                averagesCard
                earlyVsLateCard
                allShotsCard
                if let loadError { Text(loadError).font(.system(size: 12)).foregroundStyle(LS.bestEffort) }
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
                Spacer(minLength: 8)
            }
            .padding(16)
        }
        .background(LSBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .lsHidesTabBar()      // DEC-099: only Home · Stats · Lab · Coaching show the tab bar
        .task { await load() }
    }

    // MARK: header + score

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice Session").font(.system(size: 24, weight: .bold)).foregroundStyle(LS.textPrimary)
                Text("Shot Analysis · \(summary?.n_shots ?? shots.count) shots")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            Text("ENDED").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(LS.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(LS.border, lineWidth: 1))
        }
    }

    private func scoreRow(_ s: ScoreResponse) -> some View {
        HStack(spacing: 12) {
            Image("ScoreBadgePlatinum").resizable().scaledToFit().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("LaneSight Score").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.link)
                Text(Fmt.intStr(s.score)).font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
            }
            Spacer()
            HStack(spacing: 2) {
                Text((s.tier ?? "").capitalized).font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.action)
                Text("details ›").font(.system(size: 12)).foregroundStyle(LS.link)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // MARK: takeaway (session focus)

    private var takeawayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION TAKEAWAY").font(.system(size: 11, weight: .semibold)).tracking(0.88).foregroundStyle(LS.link)
            if let f = summary?.focus, f.status == "ok", let title = f.focus {
                Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                if let detail = f.detail ?? f.expected, !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color(hex: 0xB9C6D9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Keep logging shots").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text("A session takeaway appears once there are enough measured shots to spot a pattern.")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: 0xB9C6D9)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    // MARK: vs typical

    @ViewBuilder private var vsTypicalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This session vs your typical").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            if let t = summary?.typical, t.status == "ok", let tm = t.metrics {
                VStack(spacing: 8) {
                    typicalRow("Speed", "ball_speed", tm, unit: "mph")
                    typicalRow("Rev rate", "rev_rate", tm, unit: "rpm")
                    typicalRow("Entry angle", "entry_angle", tm, unit: "°")
                    typicalRow("Breakpoint", "breakpoint_board", tm, unit: "")
                }
            } else {
                let n = summary?.typical?.n_sessions ?? 0
                Text("Building — needs \(summary?.typical?.need ?? 3) comparable sessions on this pattern (you have \(n)).")
                    .font(.system(size: 12)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func typicalRow(_ label: String, _ key: String, _ typical: [String: Double], unit: String) -> some View {
        let now = summary?.mean(key)
        let typ = typical[key]
        let delta = (now != nil && typ != nil) ? now! - typ! : nil
        return HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
            Spacer()
            Text(now.map { "\(Fmt.number($0)) vs \(Fmt.number(typ ?? 0))" } ?? "—")
                .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
            if let d = delta {
                Label("\(Fmt.number(abs(d)))", systemImage: d >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold)).labelStyle(.titleAndIcon)
                    .foregroundStyle(d >= 0 ? LS.positive : LS.bestEffort).frame(width: 52, alignment: .trailing)
            }
        }
    }

    // MARK: session stats rings

    private var sessionStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session stats").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            HStack(alignment: .top, spacing: 7) {
                ring("Rev Rate", summary?.mean("rev_rate"), unit: "rpm", lo: 100, hi: 600, color: LS.dataPurple, sub: "best effort")
                ring("Speed", summary?.mean("ball_speed"), unit: "mph", lo: 8, hi: 24, color: LS.action, sub: nil)
                ring("Accuracy", nil, unit: "%", lo: 0, hi: 100, color: LS.success, sub: nil)
                ring("Consistency", summary?.consistency?.repeatability_score, unit: "%", lo: 0, hi: 100, color: LS.dataYellow, sub: "provisional")
            }
        }
    }

    private func ring(_ label: String, _ value: Double?, unit: String, lo: Double, hi: Double, color: Color, sub: String?) -> some View {
        let valueStr = value.map { String(format: $0 >= 100 ? "%.0f" : "%.1f", $0) } ?? "—"
        return MetricRing(label: label, value: valueStr, unit: value == nil ? "" : unit,
                          fraction: value.map { ($0 - lo) / (hi - lo) } ?? 0, color: color, subLabel: value == nil ? nil : sub)
    }

    // MARK: averages + spread

    private var averagesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVERAGES AND SPREAD").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            avgRow("Speed", "ball_speed", "mph")
            avgRow("Rev rate", "rev_rate", "rpm")
            avgRow("Arrows", "arrows_board", "")
            avgRow("Breakpoint", "breakpoint_board", "")
            avgRow("Entry angle", "entry_angle", "°")
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    @ViewBuilder private func avgRow(_ label: String, _ key: String, _ unit: String) -> some View {
        if let m = summary?.metrics?[key], let mean = m.mean {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                Spacer()
                Text("\(Fmt.number(mean)) ± \(Fmt.number(m.sd ?? 0))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
            }
        }
    }

    // MARK: early vs late

    @ViewBuilder private var earlyVsLateCard: some View {
        if let el = summary?.early_vs_late, !el.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Early vs late").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
                earlyLateRow("Speed", "ball_speed", el)
                earlyLateRow("Rev rate", "rev_rate", el)
                earlyLateRow("Entry angle", "entry_angle", el)
                Text("First \(el.values.first?.n_early ?? 8) vs last \(el.values.first?.n_late ?? 8) measured shots.")
                    .font(.system(size: 11)).foregroundStyle(LS.textFaint)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        }
    }

    @ViewBuilder private func earlyLateRow(_ label: String, _ key: String, _ el: [String: EarlyLate]) -> some View {
        if let e = el[key], let early = e.early, let late = e.late {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.textPrimary)
                    Spacer()
                    Text("\(Fmt.number(early)) → \(Fmt.number(late))")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(LS.textPrimary)
                    if let d = e.delta {
                        Label("\(Fmt.number(abs(d)))", systemImage: d >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .bold)).labelStyle(.titleAndIcon)
                            .foregroundStyle(d >= 0 ? LS.positive : LS.bestEffort).frame(width: 52, alignment: .trailing)
                    }
                }
                Sparkline(values: [early, late], color: LS.action).frame(height: 20)
            }
        }
    }

    // MARK: all shots table

    private var allShotsCard: some View {
        let rows = shots.sorted { ($0.created_at ?? 0) < ($1.created_at ?? 0) }
        let shown = Array(rows.suffix(8))
        return VStack(alignment: .leading, spacing: 8) {
            Text("All shots (\(rows.count))").font(.system(size: 16, weight: .bold)).foregroundStyle(LS.textPrimary)
            HStack {
                Text("#").frame(width: 24, alignment: .leading)
                Text("Res").frame(width: 44, alignment: .leading)
                Text("MPH").frame(maxWidth: .infinity, alignment: .trailing)
                Text("RPM").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Arrows").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Entry").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(LS.textSecondary)
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                if i > 0 { switchDivider(prev: shown[i - 1], cur: s) }   // DEC-097: ball/oil change mid-session
                let num = rows.count - shown.count + i + 1
                HStack {
                    Text("\(num)").frame(width: 24, alignment: .leading).foregroundStyle(LS.textSecondary)
                    Text((s.classification ?? "—").prefix(3).capitalized).frame(width: 44, alignment: .leading)
                    cell(s.metrics?.ball_speed, "%.1f")
                    cell(s.metrics?.rev_rate, "%.0f")
                    cell(s.metrics?.arrows_board, "%.1f")
                    cell(s.metrics?.entry_board, "%.1f")
                }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(LS.textPrimary)
                if s.id != shown.last?.id { Divider().overlay(LS.border) }
            }
            if rows.count > shown.count {
                Text("Showing the last \(shown.count) of \(rows.count).").font(.system(size: 11)).foregroundStyle(LS.textFaint)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    /// DEC-097: a small divider between shots where the ball or oil changed mid-session.
    @ViewBuilder private func switchDivider(prev: SessionShotRow, cur: SessionShotRow) -> some View {
        let ballChanged = cur.ball_name != nil && cur.ball_name != prev.ball_name
        let oilChanged = cur.oil_name != nil && cur.oil_name != prev.oil_name
        if ballChanged || oilChanged {
            let parts = [ballChanged ? "Switched to \(cur.ball_name!)" : nil,
                         oilChanged ? "Oil: \(cur.oil_name!)" : nil].compactMap { $0 }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .semibold))
                Text(parts.joined(separator: " · ")).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(LS.link).padding(.vertical, 3)
        }
    }

    private func cell(_ v: Double?, _ fmt: String) -> some View {
        Text(v.map { String(format: fmt, $0) } ?? "—").frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: data

    private func load() async {
        do {
            let client = try model.makeClient()
            async let sum = try? client.sessionSummary(sessionId)
            async let sh = client.sessionShots(sessionId)
            async let sc = try? client.score()
            summary = await sum
            shots = (try? await sh) ?? []
            score = await sc
        } catch { loadError = error.localizedDescription }
    }
}
