import SwiftUI

/// v3.7 Shot-card components rebuilt from the Figma (Sessions / Metric ring 413:4149, Shot result row
/// 413:4143, Metric status row 413:4155). Colors/sizes are the exact design tokens.

/// Compact circular gauge (Speed / Rev rate / Accuracy). 270° open-bottom arc with the value + unit centered.
struct MetricRing: View {
    let label: String
    let value: String        // "17.4" or "—"
    let unit: String
    let fraction: Double      // 0…1 arc fill (0 when unavailable)
    let color: Color
    var subLabel: String? = nil

    private let sweep = 0.75  // 270° gauge, open at the bottom

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xD0DEEC))
                .lineLimit(1).minimumScaleFactor(0.8)
            ZStack {
                Circle().trim(from: 0, to: sweep)
                    .stroke(LS.track, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: sweep * max(0, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 0) {
                    Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(LS.textPrimary)
                    Text(unit).font(.system(size: 7.5, weight: .medium)).foregroundStyle(LS.textSecondary)
                }
            }
            .frame(width: 48, height: 48)
            // Always reserve the sublabel line so Speed / Rev Rate / Accuracy cards are identical height
            // (the "best effort" note no longer makes Rev Rate taller than the others).
            Text(subLabel ?? " ")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(LS.bestEffort)
                .opacity(subLabel == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 7).padding(.bottom, 6).padding(.horizontal, 4)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit)\(subLabel.map { ", \($0)" } ?? "")")
    }
}

/// Strike / not-a-strike / not-read result row with the read source + confidence and a "Change" action.
struct ShotResultBadge: View {
    let state: String?          // insightsState
    let confidence: String?     // insightsConfidence
    let onChange: () -> Void

    private var result: (glyph: String, color: Color, title: String) {
        switch state {
        case "strike_repeat":                 return ("✓", LS.success, "Strike")
        case "pins_unknown", "no_reliable_data", .none, "":
                                               return ("?", LS.textSecondary, "Not read")
        default:                               return ("–", LS.dataYellow, "Not a strike")
        }
    }
    private var subtitle: String {
        let conf = (confidence ?? "").isEmpty ? "" : " · \(confidence!) confidence"
        return result.title == "Not read" ? "The deck wasn't readable" : "Read from video\(conf)"
    }

    /// Title + sublabel for reuse in the All-metrics "Result" row.
    var resultText: (title: String, sub: String) { (result.title, subtitle) }

    var body: some View {
        HStack(spacing: 12) {
            Text(result.glyph).font(.system(size: 22, weight: .heavy)).foregroundStyle(result.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(LS.textPrimary)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(LS.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: onChange) {
                Text("Change").font(.system(size: 11.5, weight: .medium)).foregroundStyle(LS.link)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LS.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LS.cardStrokeBright, lineWidth: 1))
    }
}

/// All-metrics row: status icon (left), name + context sublabel, value (right). Matches Figma 413:4155.
/// Fields are built by the caller so positional metrics ("Target 15"), the Result row, and ball dynamics
/// can share one row style.
struct MetricStatusRowV37: View {
    let name: String
    let sublabel: String?
    let value: String          // already formatted, incl. unit ("17.4 mph", "5.6 at 42 ft"); "—" when absent
    let status: MetricStatus

    private var icon: (String, Color) {
        switch status {
        case .measured:   return ("checkmark.circle.fill", LS.success)
        case .bestEffort: return ("exclamationmark.circle.fill", LS.bestEffort)
        case .unavailable: return ("exclamationmark.circle", LS.dataOrange)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.0).font(.system(size: 18)).foregroundStyle(icon.1).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(LS.textPrimary)
                if let sublabel, !sublabel.isEmpty {
                    Text(sublabel).font(.system(size: 11)).foregroundStyle(LS.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == "—" ? LS.textFaint : LS.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value == "—" ? "no value" : value), \(status.label)")
    }
}
