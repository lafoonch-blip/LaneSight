import SwiftUI

/// Active Session · Shot (v3.7 Figma 413:3804). The in-session hub: context chips, the latest shot
/// (lane recreation + outcome), a recap + next-shot card, the session rings, the carry-forward target,
/// and collapsed shot-history / lane-transition rows, with Record / End at the bottom.
///
/// Everything is live: the shot list (GET /sessions/{id}/shots), the session aggregates
/// (GET /sessions/{id}/summary → speed/rev means + consistency) and the latest shot's record/insights
/// (GET /shots/{id}). Numbers that need a per-shot target (Accuracy, the "vs target" recap checks) show
/// honest "—" / are omitted when no target was set — never fabricated.
struct SessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SessionShotRow] = []
    @State private var summary: SessionSummary?
    @State private var latest: LatestShot?
    @State private var loadError: String?
    @State private var showFeedback = false
    @State private var showSummary = false
    @State private var showLatestCard = false

    var reviewSessionId: String? = nil
    var readOnly: Bool = false

    private var effectiveSessionId: String? { reviewSessionId ?? model.activeSessionId }

    /// The latest analyzed shot, flattened for the outcome + recap cards.
    struct LatestShot {
        let id: String
        let seq: Int?
        let metrics: [String: Metric]
        let state: String?
        let confidence: String?
        let note: String?
        let classification: String?
        let rec: Recommendation?
        func v(_ k: String) -> Double? {
            guard let m = metrics[k], MetricStatus(m.status) != .unavailable else { return nil }
            return m.value
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                contextChips
                if let latest {
                    sectionHeading("Latest shot")
                    latestResultCard(latest)
                    recapCard(latest)
                } else if loadError == nil {
                    loadingCard
                }
                sessionStatsHeading
                ringRow
                sectionHeading("Target Line", action: "Why it matters")
                targetSteppers
                collapsedRow(title: "Shot history (\(rows.count))", subtitle: historySubtitle)
                collapsedRow(title: "Lane transition", subtitle: "Inferred from your line, not measured oil")
                if let loadError {
                    Text(loadError).font(.system(size: 12)).foregroundStyle(LS.bestEffort)
                }
                Spacer(minLength: 8)
                if !readOnly { bottomBar }
            }
            .padding(.horizontal, 17).padding(.vertical, 8)
        }
        .background(LSBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { header } }
        .navigationDestination(isPresented: $showLatestCard) {
            if let r = model.result { ShotCardView(result: r) }
        }
        .task { await pollLoop() }
        .refreshable { await load() }
        .sheet(isPresented: $showFeedback) {
            FeedbackView(onFinish: { endAndSummarize() }).environmentObject(model)
        }
        .fullScreenCover(isPresented: $showSummary) {
            SummaryView(summary: model.endSummary).environmentObject(model)
        }
    }

    // MARK: header + context

    private var header: some View {
        let seqTxt = latest?.seq.map { "Shot \($0)" } ?? "\(rows.count) shots"
        return VStack(spacing: 1) {
            Text(readOnly ? "Session review" : "Practice Session")
                .font(.lsRoboto(20, weight: .semibold)).foregroundStyle(LS.textPrimary)
            Text("\(model.captureMode == "form" ? "Form" : "Shot") Analysis · \(seqTxt)")
                .font(.system(size: 11)).foregroundStyle(LS.textSecondary)
        }
    }

    private var contextChips: some View {
        HStack(spacing: 6) {
            if let ball = model.currentBall?.displayName ?? model.currentBallName { chip(ball) }
            if let pat = model.selectedOilPatternName { chip(pat) }
            Spacer()
            if !readOnly {
                NavigationLink { SetupView() } label: {
                    Text("Change").font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link)
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(LS.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(LS.card, in: Capsule())
            .overlay(Capsule().strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // MARK: latest result card (lane + outcome)

    private func latestResultCard(_ s: LatestShot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LaneRecreationView(
                targetFeet: model.sessionTarget.feetBoard, targetArrows: model.sessionTarget.arrowsBoard,
                targetBreakpoint: model.sessionTarget.breakpointBoard,
                laydown: s.v("laydown_board"), actualArrows: s.v("arrows_board"),
                actualBreakpoint: s.v("breakpoint_board"), breakpointDistanceFt: s.v("breakpoint_distance"),
                entryBoard: s.v("entry_board"), entryAngle: s.v("entry_angle"),
                handed: model.handed, oilLengthFt: nil)
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 10) {
                resultBadge(s)
                outcomeItem("PIN RESULT", pinResult(s).0, color: pinResult(s).1)
                outcomeItem("TARGET", targetLine(s))
                outcomeItem("POCKET ENTRY", pocketEntry(s))
                outcomeItem("LANE", laneNote(s), lines: 2)
                Button { openLatest() } label: {
                    Text("Full analysis ›").font(.system(size: 12, weight: .medium)).foregroundStyle(LS.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func outcomeItem(_ label: String, _ value: String, color: Color = LS.textPrimary, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(LS.textSecondary)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .lineLimit(lines).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultBadge(_ s: LatestShot) -> some View {
        let (glyph, color) = pinGlyph(s)
        return Text(glyph).font(.system(size: 13, weight: .heavy)).foregroundStyle(color)
            .frame(width: 26, height: 22)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.5), lineWidth: 1))
    }

    // MARK: recap + next-shot card

    private func recapCard(_ s: LatestShot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(s.seq.map { "SHOT \($0)" } ?? "LATEST SHOT") RECAP")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.88).foregroundStyle(LS.link)
                Spacer()
                statusPill(recapPill(s).0, color: recapPill(s).1)
            }
            Text(recapHeading(s)).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(recapChecks(s)) { c in checkRow(c) }
            }
            Rectangle().fill(Color(hex: 0x284A63)).frame(height: 1).padding(.vertical, 2)
            HStack {
                Text("NEXT SHOT").font(.system(size: 11, weight: .semibold)).tracking(0.88).foregroundStyle(LS.link)
                Spacer()
                if let conf = s.confidence ?? s.rec?.confidence {
                    statusPill("Confidence: \(conf)", color: LS.dataYellow)
                }
            }
            Text(nextHeading(s)).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            if let body = nextBody(s) {
                Text(body).font(.system(size: 12)).lineSpacing(2).foregroundStyle(Color(hex: 0xB9C6D9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private struct Check: Identifiable { let id = UUID(); let ok: Bool; let label: String; let value: String }

    private func checkRow(_ c: Check) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill((c.ok ? LS.positive : LS.dataYellow).opacity(0.18))
                    .frame(width: 16, height: 16)
                Text(c.ok ? "✓" : "!").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(c.ok ? LS.positive : LS.dataYellow)
            }
            Text(c.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(c.value).font(.system(size: 11)).foregroundStyle(Color(hex: 0xB9C6D9))
        }
    }

    // MARK: session rings

    private var sessionStatsHeading: some View {
        sectionHeading("This session · \(rows.count) shots", action: "All stats")
    }

    private var ringRow: some View {
        HStack(alignment: .top, spacing: 7) {
            ring("Rev Rate", summary?.mean("rev_rate"), unit: "rpm", lo: 100, hi: 600, color: LS.dataPurple, sub: "best effort")
            ring("Speed", summary?.mean("ball_speed"), unit: "mph", lo: 8, hi: 24, color: LS.action)
            ring("Accuracy", nil, unit: "%", lo: 0, hi: 100, color: LS.success)   // needs per-shot targets → "—"
            ring("Consistency", summary?.consistency?.repeatability_score, unit: "%", lo: 0, hi: 100,
                 color: LS.dataYellow, sub: "provisional")
        }
    }

    private func ring(_ label: String, _ value: Double?, unit: String, lo: Double, hi: Double,
                      color: Color, sub: String? = nil) -> some View {
        let valueStr = value.map { String(format: $0 >= 100 ? "%.0f" : "%.1f", $0) } ?? "—"
        return MetricRing(label: label, value: valueStr, unit: value == nil ? "" : unit,
                          fraction: value.map { ($0 - lo) / (hi - lo) } ?? 0, color: color,
                          subLabel: value == nil ? nil : sub)
    }

    // MARK: target + collapsed rows

    private var targetSteppers: some View {
        HStack(spacing: 10) {
            TargetStepper(label: "FEET", value: boardBinding($model.feetBoardText), start: 25, range: 1...60)
            TargetStepper(label: "ARROWS", value: boardBinding($model.arrowsBoardText), start: 15, range: 1...39)
            TargetStepper(label: "BREAKPOINT", value: boardBinding($model.breakpointBoardText), start: 7, range: 1...39)
        }
    }

    private func boardBinding(_ text: Binding<String>) -> Binding<Int?> {
        Binding(get: { Int(text.wrappedValue.trimmingCharacters(in: .whitespaces)) },
                set: { text.wrappedValue = $0.map(String.init) ?? "" })
    }

    private func collapsedRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color(hex: 0xB9C6D9)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("›").font(.system(size: 20)).foregroundStyle(.white)
        }
        .padding(.horizontal, 15).frame(height: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 13))
                    Text(latest?.seq.map { "Record Shot \($0 + 1)" } ?? "Record shot")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("End") { showFeedback = true }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 92)
                .disabled(model.activeSessionId == nil)
        }
    }

    // MARK: shared bits

    private func sectionHeading(_ title: String, action: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if let action { Text(action).font(.system(size: 11, weight: .medium)).foregroundStyle(LS.link) }
        }
        .padding(.top, 4)
    }

    private var loadingCard: some View {
        HStack { Spacer(); ProgressView().tint(LS.action); Spacer() }
            .frame(height: 120)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private var historySubtitle: String {
        let strikes = rows.filter { ($0.classification ?? "").lowercased().contains("strike") }.count
        if rows.isEmpty { return "No shots yet" }
        return "\(strikes) strike\(strikes == 1 ? "" : "s") · \(rows.count) shot\(rows.count == 1 ? "" : "s")"
    }

    // MARK: outcome / recap derivations

    private func pinGlyph(_ s: LatestShot) -> (String, Color) {
        switch s.state {
        case "strike_repeat": return ("✓", LS.success)
        case "pins_unknown", "no_reliable_data", .none, "": return ("?", LS.textSecondary)
        default: return ("✕", LS.dataYellow)
        }
    }
    private func pinResult(_ s: LatestShot) -> (String, Color) {
        switch s.state {
        case "strike_repeat": return ("Strike", LS.success)
        case "pins_unknown", "no_reliable_data", .none, "": return ("Not read", LS.textSecondary)
        default: return ("Not a strike", LS.textPrimary)
        }
    }
    private func targetLine(_ s: LatestShot) -> String {
        guard let ta = model.sessionTarget.arrowsBoard, let a = s.v("arrows_board") else { return "Not set" }
        let off = abs(a - ta)
        return off <= 1 ? "On target at arrows" : "\(Fmt.number(off)) boards off arrows"
    }
    private func pocketEntry(_ s: LatestShot) -> String {
        guard let e = s.v("entry_board") else { return "—" }
        if let ang = s.v("entry_angle") { return "Board \(Fmt.number(e)) at \(String(format: "%.1f", ang))°" }
        return "Board \(Fmt.number(e))"
    }
    private func laneNote(_ s: LatestShot) -> String {
        if let n = s.note, !n.isEmpty { return n }
        if let r = s.rec?.reason, !r.isEmpty { return r }
        return "—"
    }

    private func recapPill(_ s: LatestShot) -> (String, Color) {
        let cls = (s.classification ?? "").capitalized
        let res = pinResult(s).0
        let txt = cls.isEmpty ? res : "\(cls) · \(res)"
        return (txt, s.state == "strike_repeat" ? LS.positive : LS.dataYellow)
    }
    private func recapHeading(_ s: LatestShot) -> String {
        switch s.state {
        case "strike_repeat": return "You hit your line"
        case "execution_miss": return "You missed your spot"
        case "pins_unknown", "no_reliable_data": return "Shot recorded"
        default: return "Clean look"
        }
    }
    private func recapChecks(_ s: LatestShot) -> [Check] {
        var out: [Check] = []
        if let a = s.v("arrows_board"), let ta = model.sessionTarget.arrowsBoard {
            out.append(Check(ok: abs(a - ta) <= 1, label: "Arrows on target", value: "\(Fmt.number(a)) vs \(Fmt.number(ta))"))
        }
        if let b = s.v("breakpoint_board"), let tb = model.sessionTarget.breakpointBoard {
            let ft = s.v("breakpoint_distance").map { " · \(Int($0.rounded())) ft" } ?? ""
            out.append(Check(ok: abs(b - tb) <= 1, label: "Breakpoint", value: "\(Fmt.number(b)) vs \(Fmt.number(tb))\(ft)"))
        }
        if let e = s.v("entry_board") {
            let ang = s.v("entry_angle").map { " · \(String(format: "%.1f", $0))°" } ?? ""
            out.append(Check(ok: true, label: "Pocket entry", value: "board \(Fmt.number(e))\(ang)"))
        }
        if let sp = s.v("ball_speed") {
            out.append(Check(ok: true, label: "Speed", value: "\(Fmt.number(sp)) mph"))
        }
        return out
    }
    private func nextHeading(_ s: LatestShot) -> String {
        if let dir = s.rec?.direction, let feet = s.rec?.move_feet {
            return "Move \(Int(feet.rounded())) board\(Int(feet.rounded()) == 1 ? "" : "s") \(dir)"
        }
        return s.state == "strike_repeat" ? "Stay on your line" : "Repeat and watch"
    }
    private func nextBody(_ s: LatestShot) -> String? {
        if let r = s.rec?.reason, !r.isEmpty {
            if let e = s.rec?.expected, !e.isEmpty { return "\(r) \(e)" }
            return r
        }
        return s.state == "strike_repeat"
            ? "You executed and struck. Repeat your line and speed."
            : nil
    }

    // MARK: data

    private func openLatest() {
        guard let id = latest?.id else { return }
        Task {
            if await model.loadShotResult(shotId: id, captureModeHint: "shot") { showLatestCard = true }
        }
    }

    private func endAndSummarize() {
        Task { try? await model.endCurrentSession(); showSummary = true }
    }

    private func pollLoop() async {
        await load()
        if readOnly { return }
        while !Task.isCancelled {
            let pending = rows.contains { $0.state == "pending" }
            if !pending && !rows.isEmpty { break }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { break }
            await load()
        }
    }

    private func load() async {
        guard let sid = effectiveSessionId else { rows = []; return }
        let client: APIClient
        do { client = try model.makeClient() } catch { loadError = error.localizedDescription; return }
        do {
            async let shotsReq = client.sessionShots(sid)
            async let sumReq = try? client.sessionSummary(sid)
            rows = try await shotsReq
            summary = await sumReq
            await loadLatest(client)
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    private func loadLatest(_ client: APIClient) async {
        let analyzed = rows.filter { $0.state == "analyzed" }
            .sorted { ($0.created_at ?? 0) > ($1.created_at ?? 0) }
        guard let row = analyzed.first else { latest = nil; return }
        guard let resp = try? await client.shot(row.id) else { return }
        let rec = resp.record
        let ins = rec?.insights
        latest = LatestShot(
            id: row.id, seq: resp.sequence,
            metrics: rec?.metrics ?? [:],
            state: ins?.state, confidence: ins?.confidence, note: ins?.note,
            classification: row.classification,
            rec: ins?.recommendations?.first { $0.direction != nil } ?? ins?.recommendations?.first)
    }
}
