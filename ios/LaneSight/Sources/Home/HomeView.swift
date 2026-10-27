import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var score: Loadable<ScoreResponse> = .idle
    @State private var history: [ScoreResponse] = []
    @State private var sessions: Loadable<[SessionRow]> = .idle
    @State private var activity: Loadable<[ActivityItem]> = .idle
    @State private var focus: FocusResponse?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                homeHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if showWelcome { welcomeStartCard }

                        LoadableView(state: score, retry: { Task { await loadScore() } }) { s in
                            if s.eligible == true {
                                ScoreCard(score: s, history: history)
                            } else {
                                buildingScoreCard(s)
                            }
                        }

                        if let f = focus, f.status == "ok", let title = f.focus {
                            nextFocusCard(f, title: title)
                        }

                        performanceLab

                        if hasSessions { recentSessions }
                        recentActivity
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
                .refreshable { await loadAll() }
            }
            .background(LSBackground())
            .navigationBarHidden(true)
            .task { await loadAll() }
        }
    }

    /// Home tab header (Main.dc.html): Settings (left) and Profile (right) at 44 pt, the official
    /// stacked logo centered. Shares the 3.0 header pattern with Stats and Lab via LSTabHeader.
    private var homeHeader: some View {
        LSTabHeader {
            Image("LaneSightLogo")
                .resizable().scaledToFit()
                .frame(maxWidth: 146, maxHeight: 48)
                .accessibilityLabel("LaneSight")
        }
    }

    /// True for a brand-new account (sessions loaded and empty): show the "Welcome to LaneSight" start card.
    private var showWelcome: Bool { if case .loaded(let rows) = sessions { return rows.isEmpty }; return false }
    /// True once there is at least one session (controls the Recent Sessions section's presence).
    private var hasSessions: Bool { if case .loaded(let rows) = sessions { return !rows.isEmpty }; return false }

    // Welcome / "Start here" card (Figma 466:4150): first-use entry point into Shot Analysis.
    private var welcomeStartCard: some View {
        NavigationLink { SetupView(initialMode: "shot") } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to LaneSight").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text("Record your first practice session. Every shot shows its result and your next move right away.")
                    .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start Shot Analysis ›").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: 0x051F3B), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: 0x007DFF).opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // "Building your LaneSight Score" card (Figma 466:4123): shown until the score is eligible. The four
    // rows are driven by the real GET /me/score eligibility (have/need) — never mock counts.
    private func buildingScoreCard(_ s: ScoreResponse) -> some View {
        let rows: [(key: String, label: String, green: Bool)] = [
            ("s_perf", "Performance (pocket, entry angle)", false),
            ("a_acc",  "Accuracy (shots with a target)", false),
            ("c_cons", "Consistency (comparable shots)", false),
            ("p_power", "Power (ball data)", true),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Building your LaneSight Score").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text("Your score appears once each part has enough shots. Until then you still see every shot’s results.")
                .font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(rows, id: \.key) { r in
                let e = s.eligibility?[r.key]
                buildingRow(label: r.label, have: e?.have ?? 0, need: e?.need ?? 0, green: r.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(hex: 0x051F3B), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.link.opacity(0.6), lineWidth: 1))
    }

    private func buildingRow(label: String, have: Int, need: Int, green: Bool) -> some View {
        let tint = green ? Color(hex: 0x3DEB7C) : LS.link
        let frac = need > 0 ? min(1, Double(have) / Double(need)) : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(have) of \(need) shots").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(green ? Color(hex: 0x3DEB7C) : LS.textSecondary)
                    .fixedSize()
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)).frame(height: 6)
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 3).fill(tint)
                        .frame(width: max(6, g.size.width * CGFloat(frac)), height: 6)
                }
                .frame(height: 6)
            }
            .frame(height: 6)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT SESSIONS").lsEyebrow()
            LoadableView(state: sessions, retry: { Task { await loadSessions() } }) { rows in
                if rows.isEmpty {
                    Text("No sessions yet. Start a practice session to see it here.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows.sorted(by: { ($0.started_at ?? 0) > ($1.started_at ?? 0) }).prefix(6)) { s in
                            if s.ended_at == nil {
                                SessionRowCard(session: s)      // a live session isn't opened for review here
                            } else {
                                // Ended session → open the read-only review: the Form-session summary for a
                                // form session (Figma 430:5744), otherwise the shot session review (6a).
                                NavigationLink {
                                    if s.isForm {
                                        FormSessionView(sessionId: s.id, readOnly: true).environmentObject(model)
                                    } else {
                                        SessionView(reviewSessionId: s.id, readOnly: true).environmentObject(model)
                                    }
                                } label: {
                                    SessionRowCard(session: s)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Recent activity (Main.dc.html + DEC-055): completed practice sessions, achievement unlocks and
    /// LaneSight tier (rank) changes only. The server (GET /me/activity) enforces this scope — uploads
    /// and other event types never appear.
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT ACTIVITY").lsEyebrow()
            LoadableView(state: activity, retry: { Task { await loadActivity() } }) { rows in
                if rows.isEmpty {
                    Text("Your sessions, uploads and achievements will show here.")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 0) {
                        let items = Array(rows.prefix(6))
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            ActivityRow(item: item)
                            if idx < items.count - 1 {
                                Divider().overlay(LS.cardStroke)
                            }
                        }
                    }
                    .lsCard(padding: 0)
                }
            }
        }
    }

    // Your Next Focus (DEC-079, Figma 453:3649): highlighted card — blue gradient + hero-stroke border.
    private func nextFocusCard(_ f: FocusResponse, title: String) -> some View {
        NavigationLink { SetupView() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR NEXT FOCUS").font(.system(size: 11, weight: .semibold)).foregroundStyle(LS.link)
                Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = f.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Practice this focus ›").font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // Performance Lab (Figma 405:3167): header + trailing chip, two photo cards (Form button is purple).
    private var performanceLab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance Lab").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text("Analyze your game. Improve every shot.").font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                }
                Spacer()
                Text("›").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(LS.raised, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.border, lineWidth: 1))
            }
            // Shared Analyze cards → the Choose-source sheet (Live session vs Upload video), same as Lab.
            AnalyzeCards()
        }
    }

    private func loadAll() async {
        await loadScore()
        await loadFocus()
        await loadSessions()
        await loadActivity()
        if model.avatarImage == nil { await model.refreshAvatar() }   // show the photo in the header
    }

    private func loadFocus() async {
        focus = try? await model.makeClient().focus()
    }

    private func loadActivity() async {
        activity = .loading
        do {
            activity = .loaded(try await model.makeClient().activity())
        } catch { activity = .failed(error.localizedDescription) }
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

    private func loadSessions() async {
        sessions = .loading
        do {
            sessions = .loaded(try await model.makeClient().listSessions())
        } catch { sessions = .failed(error.localizedDescription) }
    }
}

struct SessionRowCard: View {
    let session: SessionRow

    var body: some View {
        HStack {
            Image(systemName: "figure.bowling").foregroundStyle(LS.blue)
                .frame(width: 34, height: 34)
                .background(LS.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.isForm ? "Form session" : (session.mode ?? "Practice").capitalized).font(.lsSubheadline.bold())
                    .foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.lsCaption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            if session.ended_at == nil {
                Text("LIVE").font(.lsCaption2.bold()).foregroundStyle(LS.measured)
            }
        }
        .lsCard(padding: 12)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = session.started_at {
            parts.append(Date(timeIntervalSince1970: start).formatted(.dateTime.month().day()))
        }
        if let lane = session.lane_pair?.value, !lane.isEmpty { parts.append("Lane \(lane)") }
        if let start = session.started_at, let end = session.ended_at {
            let mins = Int((end - start) / 60)
            if mins > 0 { parts.append("\(mins) min") }
        }
        return parts.isEmpty ? "Session" : parts.joined(separator: " · ")
    }
}

/// One Home Recent activity row (Main.dc.html): a colored kind icon, a title and a subtitle.
struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.lsFootnote).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(LS.raised, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                if let sub = subtitle {
                    Text(sub).font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isTier: Bool { item.kind == "tier_promotion" || item.kind == "tier_demotion" }

    private var symbol: String {
        switch item.kind {
        case "achievement_unlocked": return "trophy.fill"
        case "tier_promotion", "tier_demotion": return "shield.fill"
        case "session_completed": return "figure.bowling"
        default: return "circle.fill"
        }
    }

    private var tint: Color { isTier ? LS.blue : (item.kind == "achievement_unlocked" ? LS.bestEffort : LS.cyan) }

    private var title: String {
        switch item.kind {
        case "achievement_unlocked":
            return "Achievement: \(item.payload?.name ?? item.ref_id ?? "unlocked")"
        case "tier_promotion":
            return "Reached \((item.payload?.to_tier ?? "a new").capitalized) tier"
        case "tier_demotion":
            return "Moved to \((item.payload?.to_tier ?? "a lower").capitalized) tier"
        case "session_completed":
            return "Completed a practice session"
        default:
            return item.ref_id ?? "Activity"
        }
    }

    private var subtitle: String? {
        if isTier, let s = item.payload?.score { return "LaneSight Score \(Int(s.rounded()))" }
        if let t = item.created_at {
            return Date(timeIntervalSince1970: t).formatted(.dateTime.month().day())
        }
        return nil
    }
}
