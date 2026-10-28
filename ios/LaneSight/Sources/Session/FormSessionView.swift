import SwiftUI

/// Form-session screen (v3.7 Figma 464:7377 Active Session·Form + 430:5744 Form session summary). One view
/// renders both: `readOnly`/ended → the summary ("TAKEAWAY" + "Done"); otherwise the live session
/// ("SO FAR" + "Record delivery N" + "End session"). All numbers come from GET /sessions/{id}/form-summary
/// (server-computed from measured deliveries). Form is diagnostic only — never part of the LaneSight score.
struct FormSessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    var readOnly: Bool = false

    @State private var data: Loadable<FormSessionSummary> = .idle

    private var ended: Bool { readOnly || (data.value?.in_progress == false) }

    var body: some View {
        ScrollView {
            LoadableView(state: data, retry: { Task { await load() } }) { s in
                VStack(alignment: .leading, spacing: 18) {
                    contextLine(s)
                    if let t = s.takeaway, let text = t.text { takeawayCard(text: text, drill: t.drill) }
                    repeatabilityCard(s)
                    if let evl = s.early_vs_late, !evl.isEmpty { earlyVsLate(evl) }
                    deliveriesSection(s)
                    cta(s)
                }
                .padding(16)
            }
        }
        .background(LSBackground())
        .navigationTitle("Form session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        // DEC-096: record a delivery over the Active (form) session; every analysis returns here. Reload on close.
        .fullScreenCover(isPresented: $model.inLiveCapture, onDismiss: { Task { await load() } }) {
            CaptureView().environmentObject(model)
        }
    }

    private func load() async {
        data = .loading
        do { data = .loaded(try await model.makeClient().formSessionSummary(sessionId)) }
        catch { data = .failed(error.localizedDescription) }
    }

    // "Form Analysis · side view · 8 deliveries · in progress|ended"
    private func contextLine(_ s: FormSessionSummary) -> some View {
        let parts = ["Form Analysis", viewLabel(s.view), "\(s.n_deliveries ?? 0) deliveries",
                     ended ? endedText(s) : "in progress"].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 13)).foregroundStyle(LS.textSecondary)
    }

    // SO FAR / TAKEAWAY blue hero card.
    private func takeawayCard(text: String, drill: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ended ? "TAKEAWAY" : "SO FAR")
                .font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(LS.link)
            Text(text).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let drill { Text(drill).font(.system(size: 13)).foregroundStyle(LS.textSecondary)
                .fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    private func repeatabilityCard(_ s: FormSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REPEATABILITY ACROSS DELIVERIES")
                .font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            ForEach(s.repeatability ?? []) { r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.label ?? "").font(.system(size: 14)).foregroundStyle(LS.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.display ?? "—").font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.textPrimary)
                        .fixedSize()
                    statusChip(r.status)
                }
            }
            if let note = s.note {
                Text(note).font(.system(size: 11)).foregroundStyle(LS.textFaint)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // "Early vs late" — a mini trend per metric with the first→last shift + chip.
    private func earlyVsLate(_ evl: [String: FormEarlyLate]) -> some View {
        let order: [(key: String, label: String, unit: String)] = [
            ("release_timing", "Release timing (s vs slide stop)", "s"),
            ("approach_time", "Approach time (s)", "s"),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Early vs late").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("First 4 vs last 4").font(.system(size: 12)).foregroundStyle(LS.link)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(order.filter { evl[$0.key] != nil }, id: \.key) { row in
                    let e = evl[row.key]!
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text(trendText(e, unit: row.unit))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(trendColor(e))
                        }
                        trendSparkline(e.series ?? [])
                        Text(driftNarrative(row.key, e)).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                    }
                }
            }
            .padding(14)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        }
    }

    private func deliveriesSection(_ s: FormSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("All deliveries (\(s.n_deliveries ?? 0))").font(.system(size: 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                Spacer()
                Text("Sort").font(.system(size: 13)).foregroundStyle(LS.link)
            }
            VStack(spacing: 10) {
                ForEach(s.deliveries ?? []) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Delivery \(d.seq ?? 0)").font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                            Text(deliverySub(d)).font(.system(size: 12)).foregroundStyle(LS.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(LS.textFaint)
                    }
                    .padding(14)
                    .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder private func cta(_ s: FormSessionSummary) -> some View {
        if ended {
            Button { dismiss() } label: {
                HStack(spacing: 8) { Text("Done"); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
        } else {
            // DEC-096: Record delivery opens the camera over this Active Session; End session ends it in place
            // and reloads into the ended (TAKEAWAY) summary — never bounces to Setup or out of the session.
            Button { model.captureMode = "form"; model.inLiveCapture = true } label: {
                HStack(spacing: 8) { Text("Record delivery \((s.n_deliveries ?? 0) + 1)"); Image(systemName: "arrow.right") }
                    .frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButtonStyle())
            Button("End session") { Task { try? await model.endCurrentSession(); await load() } }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.link)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
    }

    // MARK: helpers

    private func statusChip(_ status: String?) -> some View {
        let (txt, color): (String, Color) = {
            switch status {
            case "steady": return ("steady", LS.success)
            case "drifting": return ("drifting", Color(hex: 0xFA923C))
            case "best_effort": return ("best effort", LS.bestEffort)
            case "varied": return ("varied", Color(hex: 0xFA923C))
            default: return ("building", LS.textSecondary)
            }
        }()
        return Text(txt).font(.system(size: 12, weight: .semibold)).foregroundStyle(color).fixedSize()
    }

    private func trendSparkline(_ series: [Double]) -> some View {
        GeometryReader { g in
            let vals = series
            if vals.count >= 2 {
                let lo = vals.min()!, hi = vals.max()!
                let span = (hi - lo) == 0 ? 1 : (hi - lo)
                Path { p in
                    for (i, v) in vals.enumerated() {
                        let x = g.size.width * CGFloat(i) / CGFloat(vals.count - 1)
                        let y = g.size.height * (1 - CGFloat((v - lo) / span))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(LS.action, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 40)
        .background(LS.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func trendText(_ e: FormEarlyLate, unit: String) -> String {
        let a = e.early ?? 0, b = e.late ?? 0, d = e.delta ?? (b - a)
        let arrow = abs(d) < 0.02 ? "–" : (d > 0 ? "▲" : "▼")
        let word = abs(d) < 0.02 ? "steady" : (d > 0 ? "later" : "earlier")
        return "\(fmt(a)) → \(fmt(b))  \(arrow) \(word)"
    }
    private func trendColor(_ e: FormEarlyLate) -> Color {
        abs(e.delta ?? 0) < 0.02 ? LS.textSecondary : Color(hex: 0xFA923C)
    }
    private func driftNarrative(_ key: String, _ e: FormEarlyLate) -> String {
        let d = e.delta ?? 0
        if abs(d) < 0.02 { return key == "approach_time" ? "Rhythm held all session" : "Held steady all session" }
        if key == "release_timing" { return d > 0 ? "Releasing later as you tired" : "Releasing earlier as you tired" }
        return d > 0 ? "Slower approach late in the session" : "Quicker approach late in the session"
    }
    private func deliverySub(_ d: FormDelivery) -> String {
        var parts: [String] = []
        if let r = d.release_offset {
            let side = r >= 0 ? "late" : "early"
            parts.append(String(format: "Release %.2fs %@", abs(r), side))
        }
        if let s = d.swing_total { parts.append(String(format: "swing %.2fs", s)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private func viewLabel(_ v: String?) -> String? {
        switch v { case "down_lane": return "down-lane view"; case "rear": return "rear view"
        case "side": return "side view"; case .some(let s) where !s.isEmpty && s != "unknown": return "\(s) view"
        default: return nil }
    }
    private func endedText(_ s: FormSessionSummary) -> String {
        guard let e = s.ended_at else { return "ended" }
        return "ended \(Date(timeIntervalSince1970: e).formatted(.dateTime.hour().minute()))"
    }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}
