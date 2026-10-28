import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    // DEC-099: Home's data lives in the shared tab store — fetched in parallel, published at once, refreshed
    // silently on revisit (no section-by-section pop-in).
    @EnvironmentObject var tabs: TabDataStore
    private var score: Loadable<ScoreResponse> { tabs.home.score }
    private var history: [ScoreResponse] { tabs.home.history }
    private var sessions: Loadable<[SessionRow]> { tabs.home.sessions }
    private var activity: Loadable<[ActivityItem]> { tabs.home.activity }
    private var focus: FocusResponse? { tabs.home.focus }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                homeHeader
                ScrollView {
                    if !tabs.homeReady {
                        LSPageLoading()
                    } else {
                    VStack(alignment: .leading, spacing: 18) {
                        if showWelcome { welcomeStartCard }

                        // DEC-083: Home keeps the real score card in both states — ScoreCard renders the
                        // locked "BUILDING" treatment (greyed badge, "Score unlocks · N%", per-part progress)
                        // until the score is eligible, so the switch to a live score feels seamless.
                        LoadableView(state: score, retry: { Task { await loadAll() } }) { s in
                            ScoreCard(score: s, history: history)
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

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT SESSIONS").lsEyebrow()
            LoadableView(state: sessions, retry: { Task { await loadAll() } }) { rows in
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
            LoadableView(state: activity, retry: { Task { await loadAll() } }) { rows in
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
        await tabs.load(.home, model: model)
        if !model.homeLoaded {
            withAnimation(.easeOut(duration: 0.35)) { model.homeLoaded = true }
            // Home is up — warm Stats + Lab in the background so their first visit is instant too.
            Task { await tabs.prefetchOtherTabs(model: model) }
        }
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
