import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var score: Loadable<ScoreResponse> = .idle
    @State private var history: [ScoreResponse] = []
    @State private var sessions: Loadable<[SessionRow]> = .idle

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                homeHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LoadableView(state: score, retry: { Task { await loadScore() } }) { s in
                            ScoreCard(score: s, history: history)
                        }

                        NavigationLink { SetupView() } label: { Text("Start practice") }
                            .buttonStyle(PrimaryButtonStyle())

                        recentSessions
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
    /// stacked logo centered. Other tabs' headers are a later step.
    private var homeHeader: some View {
        HStack(spacing: 12) {
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(LS.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(LS.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LS.border, lineWidth: 1))
            }
            .accessibilityLabel("Settings")

            Spacer(minLength: 0)

            Image("LaneSightLogo")
                .resizable().scaledToFit()
                .frame(maxWidth: 146, maxHeight: 48)
                .accessibilityLabel("LaneSight")

            Spacer(minLength: 0)

            NavigationLink { ProfileView() } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LS.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(LS.selected, in: Circle())
                    .overlay(Circle().strokeBorder(LS.action, lineWidth: 2))
            }
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT SESSIONS").lsEyebrow()
            LoadableView(state: sessions, retry: { Task { await loadSessions() } }) { rows in
                if rows.isEmpty {
                    Text("No sessions yet. Start a practice session to see it here.")
                        .font(.callout).foregroundStyle(LS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lsCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(rows.sorted(by: { ($0.started_at ?? 0) > ($1.started_at ?? 0) }).prefix(6)) { s in
                            SessionRowCard(session: s)
                        }
                    }
                }
            }
        }
    }

    private func loadAll() async {
        await loadScore()
        await loadSessions()
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
                .background(LS.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text((session.mode ?? "Practice").capitalized).font(.subheadline.bold())
                    .foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(LS.textSecondary)
            }
            Spacer()
            if session.ended_at == nil {
                Text("LIVE").font(.caption2.bold()).foregroundStyle(LS.measured)
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
