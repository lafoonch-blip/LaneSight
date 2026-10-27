import SwiftUI

/// Session summary (Summary.dc.html). Uses the richer POST /sessions/{id}/end response: score + tier
/// change, personal best, batched achievement unlocks, and any pending notifications. A tier
/// celebration (if one was raised at session end) is surfaced full-screen once, then batched unlocks
/// are listed inline. Fields the API doesn't return are omitted — never faked.
struct SummaryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let summary: EndSessionResponse?

    @State private var celebration: AppNotification?
    @State private var surfaced = false

    /// Achievement unlock notifications carry names/descriptions; tier ones drive the celebration.
    private var unlockNotifs: [AppNotification] {
        (summary?.notifications ?? []).filter { $0.kind == "achievement_popup" }
    }
    private var tierNotif: AppNotification? {
        (summary?.notifications ?? []).first { $0.kind == "tier_celebration" || $0.kind == "tier_banner" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock
                    scoreCard
                    if let te = summary?.tier_event { tierChangeCard(te) }
                    unlockedSection
                    Spacer(minLength: 8)
                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LSBackground())
        }
        .task { await surface() }
        .fullScreenCover(item: $celebration) { n in
            NavigationStack {
                CelebrationRouter(notification: n, onClose: { celebration = nil })
                    .environmentObject(model)
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SESSION COMPLETE").lsEyebrow()
            Text("Practice")
                .font(.lsTitle2.bold()).foregroundStyle(LS.textPrimary)
            if let n = summary?.shots {
                Text("\(n) shot\(n == 1 ? "" : "s")").font(.lsCallout).foregroundStyle(LS.textSecondary)
            }
        }
    }

    @ViewBuilder private var scoreCard: some View {
        if let score = summary?.score {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LANESIGHT SCORE · BETA").lsEyebrow()
                    Spacer()
                    if summary?.personal_best == true {
                        Label("Personal best", systemImage: "star.fill")
                            .font(.lsCaption2.bold()).foregroundStyle(LS.bestEffort)
                    }
                }
                if score.eligible == true, let v = score.score {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(Int(v.rounded())))
                            .font(.lsRoboto(44, weight: .bold))
                            .foregroundStyle(LS.textPrimary)
                        if let tier = score.tier {
                            Text(tier.uppercased()).font(.lsSubheadline.bold()).foregroundStyle(LS.cyan)
                        }
                    }
                } else {
                    Label("Still building your score", systemImage: "hourglass")
                        .font(.lsCallout).foregroundStyle(LS.textSecondary)
                }
            }
            .lsCard()
        }
    }

    private func tierChangeCard(_ te: TierEvent) -> some View {
        let promo = te.kind == "promotion"
        return HStack(spacing: 12) {
            TierBadge(tier: te.to_tier, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(promo ? "Reached \((te.to_tier ?? "").capitalized)" : "Moved to \((te.to_tier ?? "").capitalized)")
                    .font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                if let from = te.from_tier {
                    Text(promo ? "Up from \(from.capitalized)" : "From \(from.capitalized)")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer()
            Image(systemName: promo ? "arrow.up.circle.fill" : "arrow.down.circle")
                .foregroundStyle(promo ? LS.measured : LS.bestEffort)
        }
        .lsCard()
    }

    @ViewBuilder private var unlockedSection: some View {
        let extra = (summary?.unlocked?.count ?? 0) - unlockNotifs.count
        if !unlockNotifs.isEmpty || extra > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("UNLOCKED THIS SESSION").font(.lsCaption.weight(.semibold)).tracking(1.1).foregroundStyle(LS.cyan)
                VStack(spacing: 0) {
                    ForEach(Array(unlockNotifs.enumerated()), id: \.element.id) { idx, n in
                        HStack(spacing: 12) {
                            AchievementBadge(category: n.payload?.category, unlocked: true, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.payload?.name ?? "Achievement")
                                    .font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                                if let d = n.payload?.description {
                                    Text(d).font(.lsCaption2).foregroundStyle(LS.textSecondary)
                                }
                            }
                            Spacer()
                            Text("NEW").font(.lsCaption2.bold()).foregroundStyle(LS.cyan)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        if idx != unlockNotifs.count - 1 { Divider().overlay(LS.cardStroke).padding(.leading, 14) }
                    }
                }
                .lsCard(padding: 0)
                if extra > 0 {
                    Text("+\(extra) more unlocked — see Achievements.")
                        .font(.lsCaption).foregroundStyle(LS.textSecondary)
                }
            }
        }
    }

    /// Mark all session-end notifications delivered (so they don't re-pop on the next shot) and
    /// present the tier celebration full-screen once, at this quiet moment.
    private func surface() async {
        guard !surfaced else { return }
        surfaced = true
        for n in (summary?.notifications ?? []) { await model.markNotificationDelivered(n.id) }
        if let tier = tierNotif { celebration = tier }
    }
}
