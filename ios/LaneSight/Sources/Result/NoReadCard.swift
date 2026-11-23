import SwiftUI

/// Shown instead of the lane view + empty gauges when a shot produced no measured number (2026-11-23).
/// Says what went wrong in plain words — mapped from the engine's reason codes / notes, never the raw text —
/// and gives one concrete filming tip. No coaching move: there's nothing measured to base one on.
struct NoReadCard: View {
    let result: ShotResult

    private var notes: String {
        let metricNotes = result.metrics.compactMap { $0.1.note }.joined(separator: " ")
        let stageNotes = result.stageReport.values.compactMap { $0.reason_code ?? $0.reason }.joined(separator: " ")
        return (metricNotes + " " + stageNotes).lowercased()
    }

    /// Plain-English reasons, most important first (speed, then revs, then the lane line).
    private var reasons: [String] {
        let n = notes
        var out: [String] = []
        if n.contains("lane") && (n.contains("not found") || n.contains("not detected") || n.contains("no lane")) {
            out.append("We couldn't find the lane in the video.")
        }
        if n.contains("pin_impact_not_detected") || n.contains("pin contact not detected") || n.contains("pins deck not located") {
            out.append("We couldn't see the ball reach the pins, so speed can't be timed.")
        }
        if n.contains("track_too_sparse") || n.contains("track points") || n.contains("sparse") {
            out.append("The ball wasn't tracked for enough of the lane to read your line.")
        }
        if n.contains("spin period") || n.contains("rev") {
            out.append("The ball's markings weren't clear enough to count revs.")
        }
        if out.isEmpty { out.append("The ball couldn't be followed clearly enough to measure this shot.") }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LS.bestEffort)
                Text("We couldn't measure this shot").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reasons, id: \.self) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(LS.textSecondary).padding(.top, 7)
                        Text(r).font(.system(size: 15)).foregroundStyle(LS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider().overlay(LS.border)
            VStack(alignment: .leading, spacing: 4) {
                Text("For the next one").font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.link)
                Text("Film from behind the bowler, phone steady, with the whole lane — foul line to the pins — in frame. "
                     + "Good light on the pin deck helps.")
                    .font(.system(size: 14)).foregroundStyle(LS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }
}
