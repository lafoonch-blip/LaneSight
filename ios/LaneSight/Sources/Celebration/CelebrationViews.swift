import SwiftUI

// MARK: - Celebration surfaces (Unlock.dc.html / TierUp.dc.html)
//
// Driven entirely by GET /me/notifications. An achievement_popup becomes an Unlock card; a
// tier_celebration / tier_banner becomes a full-screen TierUp. Ordering (tier > achievement, ≤1 per
// shot) is handled upstream by the server's priority sort — a surface just renders what it's given.
// All text/values come from the notification payload; nothing is fabricated.

/// Routes a pending notification to the right celebration surface. Use as the body of a fullScreenCover.
struct CelebrationRouter: View {
    @EnvironmentObject var model: AppModel
    let notification: AppNotification
    var onClose: () -> Void = {}

    var body: some View {
        switch notification.kind {
        case "tier_celebration", "tier_banner":
            TierUpView(notification: notification, onClose: onClose)
        default:
            UnlockView(notification: notification, onClose: onClose)
        }
    }
}

/// Achievement unlocked popup. "View" opens the achievement; both View and Dismiss POST dismiss.
struct UnlockView: View {
    @EnvironmentObject var model: AppModel
    let notification: AppNotification
    var onClose: () -> Void = {}

    private var p: NotifPayload? { notification.payload }
    private var valueLine: String? {
        guard let v = p?.value?.display else { return nil }
        if let t = p?.target?.display { return "\(v) / \(t)" }
        return v
    }

    var body: some View {
        ZStack {
            LS.bgAuth.ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer()
                Text("ACHIEVEMENT UNLOCKED")
                    .font(.lsCaption.weight(.heavy)).tracking(1.5).foregroundStyle(LS.cyan)
                AchievementBadge(category: p?.category, unlocked: true, size: 112)
                Text(p?.name ?? "Achievement")
                    .font(.lsRoboto(26, weight: .bold)).foregroundStyle(LS.textPrimary)
                    .multilineTextAlignment(.center)
                if let d = p?.description {
                    Text(d).font(.lsCallout).foregroundStyle(LS.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let valueLine {
                    Text(valueLine)
                        .font(.lsTitle3.bold().monospacedDigit()).foregroundStyle(LS.cyan)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(LS.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                VStack(spacing: 8) {
                    if let achId = p?.achievement_id {
                        NavigationLink {
                            AchievementDetailView(achievementId: achId)
                        } label: { Text("View achievement") }
                            .buttonStyle(PrimaryButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded { dismiss() })
                    }
                    Button("Dismiss") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Achievement unlocked, \(p?.name ?? "")")
    }

    private func dismiss() {
        let id = notification.id
        Task { await model.dismissNotification(id) }
        onClose()
    }
}

/// Full-screen tier celebration. Continue → POST dismiss.
struct TierUpView: View {
    @EnvironmentObject var model: AppModel
    let notification: AppNotification
    var onClose: () -> Void = {}

    private var p: NotifPayload? { notification.payload }
    private var tier: String { (p?.to_tier ?? "").uppercased() }
    private var isBanner: Bool { notification.kind == "tier_banner" }

    var body: some View {
        ZStack {
            LS.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer().frame(height: 20)
                Text(isBanner ? "TIER REGAINED" : "NEW TIER REACHED")
                    .font(.lsCaption.weight(.heavy)).tracking(2).foregroundStyle(LS.textSecondary)
                TierBadge(tier: p?.to_tier, size: 180)
                Text(tier.isEmpty ? "NEW TIER" : tier)
                    .font(.lsRoboto(34, weight: .bold)).tracking(1)
                    .foregroundStyle(LS.textPrimary)
                if let score = p?.score {
                    (Text("Your LaneSight Score reached ")
                        .foregroundStyle(LS.textSecondary)
                     + Text("\(Int(score.rounded()))").bold().foregroundStyle(LS.textPrimary))
                        .font(.lsCallout).multilineTextAlignment(.center)
                }
                nextTierCard
                Spacer()
                Button("Continue") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New tier reached, \(tier)")
    }

    @ViewBuilder private var nextTierCard: some View {
        if let next = p?.next_tier, let points = p?.points, points > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Next: \(next.capitalized)").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
                    Spacer()
                    Text("\(Int(points.rounded())) points to go")
                        .font(.lsSubheadline.bold()).foregroundStyle(LS.textPrimary)
                }
            }
            .lsCard()
        } else if p?.next_tier == nil {
            Text("Top tier reached.").font(.lsSubheadline).foregroundStyle(LS.textSecondary)
        }
    }

    private func dismiss() {
        let id = notification.id
        Task { await model.dismissNotification(id) }
        onClose()
    }
}

// MARK: - Badges

/// A stylized tier badge shield. Color keys off the tier name; falls back to a neutral slate.
struct TierBadge: View {
    let tier: String?
    var size: CGFloat = 64

    private var stroke: Color {
        switch tier?.lowercased() {
        case "bronze": return Color(hex: 0xCD7F32)
        case "silver": return Color(hex: 0xC9D4EA)
        case "gold": return Color(hex: 0xFFC970)
        case "platinum": return Color(hex: 0xB9D2F5)
        case "onyx": return Color(hex: 0x8A97B2)
        default: return LS.textSecondary
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable().scaledToFit()
                .foregroundStyle(LS.card)
            Image(systemName: "shield")
                .resizable().scaledToFit()
                .foregroundStyle(stroke)
            Image(systemName: "figure.bowling")
                .resizable().scaledToFit()
                .frame(width: size * 0.34, height: size * 0.34)
                .foregroundStyle(stroke)
        }
        .frame(width: size, height: size * 1.08)
        .accessibilityHidden(true)
    }
}

/// An achievement badge tile keyed by category (used in Unlock + Achievements showcase).
struct AchievementBadge: View {
    var category: String?
    var unlocked: Bool = false
    var size: CGFloat = 52

    private var tint: Color {
        switch category {
        case "accuracy": return LS.cyan
        case "power": return LS.bestEffort
        case "consistency": return LS.measured
        case "tier": return LS.action
        case "form": return LS.dataPurple
        case "progress": return LS.blue
        default: return LS.cyan
        }
    }

    private var symbol: String {
        switch category {
        case "accuracy": return "scope"
        case "power": return "bolt.fill"
        case "consistency": return "metronome"
        case "tier": return "shield.fill"
        case "form": return "figure.bowling"
        case "progress": return "chart.line.uptrend.xyaxis"
        case "volume": return "square.stack.3d.up.fill"
        case "arsenal": return "circle.circle"
        case "streak": return "flame.fill"
        case "onboarding": return "flag.checkered"
        default: return "rosette"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42))
            .foregroundStyle(unlocked ? tint : LS.textFaint)
            .frame(width: size, height: size)
            .background((unlocked ? tint : LS.textFaint).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(unlocked ? tint : LS.cardStroke, lineWidth: 2))
            .accessibilityHidden(true)
    }
}
