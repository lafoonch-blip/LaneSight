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
                        LoadableView(state: score, retry: { Task { await loadScore() } }) { s in
                            ScoreCard(score: s, history: history)
                        }

                        if let f = focus, f.status == "ok", let title = f.focus {
                            nextFocusCard(f, title: title)
                        }

                        performanceLab

                        recentSessions
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
                                // Ended session → open the read-only review (design SessionReview / 6a).
                                NavigationLink {
                                    SessionView(reviewSessionId: s.id, readOnly: true).environmentObject(model)
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
                    Text("No activity yet. Finish a session or earn an achievement to see it here.")
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

    private func nextFocusCard(_ f: FocusResponse, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR NEXT FOCUS").lsEyebrow()
            Text(title).font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
            if let detail = f.detail, !detail.isEmpty {
                Text(detail).font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            NavigationLink { SetupView() } label: {
                HStack(spacing: 4) {
                    Text("Practice this focus")
                    Image(systemName: "chevron.right").font(.lsCaption)
                }
                .font(.lsSubheadline.weight(.semibold)).foregroundStyle(LS.action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var performanceLab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance Lab").font(.lsTitle3.weight(.semibold)).foregroundStyle(LS.textPrimary)
                Text("Analyze your game. Improve every shot.").font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
            HStack(alignment: .top, spacing: 12) {
                labCard(mode: "shot", title: "Shot Analysis",
                        desc: "Track ball motion, lane reaction and results.",
                        symbol: "scope", action: "Start Shot Analysis")
                labCard(mode: "form", title: "Form Analysis",
                        desc: "Analyze approach, timing, release and mechanics.",
                        symbol: "figure.bowling", action: "Start Form Analysis")
            }
        }
    }

    private func labCard(mode: String, title: String, desc: String, symbol: String, action: String) -> some View {
        NavigationLink { SetupView(initialMode: mode) } label: {
            VStack(alignment: .leading, spacing: 8) {
                // TODO(v3.7 assets): swap this placeholder for the Figma Shot/Form card photo.
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LS.raised)
                    .frame(height: 84)
                    .overlay(Image(systemName: symbol).font(.title2).foregroundStyle(LS.action))
                Text(title).font(.lsHeadline).foregroundStyle(LS.textPrimary)
                Text(desc).font(.lsCaption).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(action).font(.lsCaption.weight(.semibold)).foregroundStyle(LS.onAction)
                    .padding(.vertical, 7).frame(maxWidth: .infinity)
                    .background(LS.action, in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lsCard(padding: 12)
        }
        .buttonStyle(.plain)
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
                Text((session.mode ?? "Practice").capitalized).font(.lsSubheadline.bold())
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
