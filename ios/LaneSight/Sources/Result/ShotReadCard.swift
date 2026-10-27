import SwiftUI

/// DEC-088/090 "Shot read" card: the two-part read (YOUR THROW / LANE & PINS) as rings, plus the single
/// COACH action. Everything is live from the server coach block (insights.throw/lane/coach). A ring with no
/// measured value shows "—" and no arc — never a fabricated number.
struct ShotReadCard: View {
    let result: ShotResult

    private func metric(_ k: String) -> Double? { result.metrics.first(where: { $0.0 == k })?.1.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            throwSection
            Divider().overlay(LS.border)
            laneSection
            coachBox
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }

    // MARK: Your throw

    private var throwStatus: String { result.coachThrow?.status ?? "building" }
    private var throwColor: Color {
        switch throwStatus { case "good": return LS.positive; case "off": return LS.dataOrange; default: return LS.textSecondary }
    }

    private var throwSection: some View {
        let r = result.coachThrow?.rings
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("YOUR THROW", badge: result.coachThrow?.verdict, color: throwColor)
            HStack(alignment: .top, spacing: 6) {
                ring("Speed", r?["speed"]?.value, unit: "mph", sub: r?["speed"]?.vs, lo: 8, hi: 24, color: throwColor)
                ring("Rev rate", r?["rev"]?.value, unit: "rpm", sub: r?["rev"]?.vs, lo: 100, hi: 600, color: throwColor)
                ring("Accuracy", r?["accuracy"]?.value, unit: "bd", sub: r?["accuracy"]?.vs, lo: 1, hi: 39, color: throwColor)
            }
        }
    }

    // MARK: Lane & pins

    private var laneStatus: String { result.coachLane?.status ?? "not_read" }
    private var laneColor: Color {
        switch laneStatus { case "good": return LS.positive; case "miss": return LS.dataOrange; default: return LS.textSecondary }
    }
    private var laneRead: Bool { laneStatus != "not_read" }

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("LANE & PINS", badge: laneRead ? result.coachLane?.explanation : "Not read", color: laneColor)
            HStack(alignment: .top, spacing: 6) {
                ring("Entry point", laneRead ? (result.coachLane?.entry_board ?? metric("entry_board")) : nil,
                     unit: "bd", sub: laneRead ? "pocket 17.5" : "Not read", lo: 0, hi: 39, color: laneColor)
                ring("Entry angle", laneRead ? (result.coachLane?.entry_angle ?? metric("entry_angle")) : nil,
                     unit: "°", sub: laneRead ? "carries 4–6°" : "Not read", lo: 2, hi: 8, color: laneColor)
                ring("Power", laneRead ? result.impactEnergyJ : nil, unit: "J",
                     sub: "impact energy", lo: 0, hi: 300, color: laneColor)
            }
        }
    }

    // MARK: Coach

    private var coachBox: some View {
        let action = result.coachAction?.action
        let tag: String = {
            switch action {
            case "keep": return "Keep it"
            case "lane_move": return "Lane move"
            case "no_move": return "No move"
            default: return "No move yet"
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(LS.link)
                Text(tag).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(LS.link)
            }
            Text(result.coachAction?.text ?? "Keep repeating your line.")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: 0x04213F), Color(hex: 0x031B35)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LS.heroStroke, lineWidth: 1))
    }

    // MARK: pieces

    private func sectionHeader(_ title: String, badge: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(LS.textSecondary)
            Spacer(minLength: 8)
            if let badge, !badge.isEmpty {
                Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func ring(_ label: String, _ value: Double?, unit: String, sub: String?, lo: Double, hi: Double, color: Color) -> some View {
        let frac = value.map { max(0, min(1, ($0 - lo) / (hi - lo))) }
        let valStr = value.map { String(format: $0 >= 100 ? "%.0f" : ($0 == $0.rounded() ? "%.0f" : "%.1f"), $0) } ?? "—"
        return VStack(spacing: 6) {
            ZStack {
                ArcGauge(fraction: frac, color: color)
                VStack(spacing: 0) {
                    Text(valStr).font(.system(size: valStr.count > 4 ? 15 : 18, weight: .bold)).foregroundStyle(LS.textPrimary)
                    if value != nil { Text(unit).font(.system(size: 11)).foregroundStyle(LS.textSecondary) }
                }
            }
            .frame(width: 68, height: 68)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(LS.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Text(sub ?? " ").font(.system(size: 12, weight: .semibold)).foregroundStyle(LS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(LS.raised, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 68 pt ring: a 270° arc starting at 135° (bottom-left), track #153b51, progress in the status color.
/// No arc drawn when `fraction` is nil (metric not read).
struct ArcGauge: View {
    let fraction: Double?
    var color: Color
    private let start = Angle(degrees: 135), sweep = 270.0

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: sweep / 360)
                .stroke(Color(hex: 0x153B51), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(start)
            if let f = fraction {
                Circle().trim(from: 0, to: (sweep / 360) * f)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(start)
            }
        }
    }
}
