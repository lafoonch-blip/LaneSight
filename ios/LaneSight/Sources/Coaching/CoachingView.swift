import SwiftUI

/// Coaching tab — "Coaching is on the way" (DEC-084). A tappable tab (not a dimmed one, which reads as
/// broken) that sets expectations and measures interest. Coach features only — NO AI chat — consistent with
/// DEC-046/047 and the 2026-10-27 coaching review. "Notify me" saves a per-user flag (PUT /me/notify) so the
/// one launch notification can go out later.
struct CoachingView: View {
    @EnvironmentObject var model: AppModel
    @State private var notifying = false
    @State private var notified = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LSTabHeader(title: "Coaching")
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        comingCard
                        untilThenCard
                        notifyButton
                        Text("Coaching connects you with a real coach. LaneSight's in-app advice stays rules-based — there's no AI chat.")
                            .font(.system(size: 11)).foregroundStyle(LS.textFaint)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
            }
            .background(LSBackground())
            .navigationBarHidden(true)
            .task { await loadNotify() }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(LS.action.opacity(0.14)).frame(width: 84, height: 84)
                Image(systemName: "graduationcap.fill").font(.system(size: 36)).foregroundStyle(LS.action)
            }
            Text("Coaching is on the way").font(.system(size: 22, weight: .bold)).foregroundStyle(LS.textPrimary)
                .multilineTextAlignment(.center)
            Text("Work with a coach you choose, right inside LaneSight.")
                .font(.system(size: 13)).foregroundStyle(LS.textSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    private var comingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT'S COMING").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(LS.action)
            comingRow("square.and.arrow.up", "Share with your coach",
                      "Send sessions, shots and form positions to a coach you choose.")
            comingRow("pencil.and.list.clipboard", "Notes and drills",
                      "Get notes and drills from your coach tied to specific shots.")
            comingRow("checkmark.seal", "See what helped",
                      "Track whether a suggested change actually improved your game.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    private func comingRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(LS.raised).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(LS.action)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                Text(detail).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var untilThenCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNTIL THEN").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(LS.link)
            Text("Every shot already gives you a next move, and Home shows your next focus. Those keep guiding you while coaching is built.")
                .font(.system(size: 13)).foregroundStyle(LS.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    @ViewBuilder private var notifyButton: some View {
        if notified {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LS.positive)
                Text("We'll let you know").font(.system(size: 16, weight: .semibold)).foregroundStyle(LS.textPrimary)
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(LS.positive.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.positive.opacity(0.5), lineWidth: 1))
        } else {
            Button { Task { await notifyMe() } } label: {
                HStack { Text("Notify me when it's ready"); if busy { ProgressView().tint(LS.onAction) } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private func loadNotify() async {
        notified = (try? await model.makeClient().getCoachingNotify()) ?? false
    }

    private func notifyMe() async {
        busy = true
        defer { busy = false }
        do {
            try await model.makeClient().setCoachingNotify()
            withAnimation { notified = true }
        } catch {
            // Leave the button in place so the user can retry; no fake success.
        }
    }
}
