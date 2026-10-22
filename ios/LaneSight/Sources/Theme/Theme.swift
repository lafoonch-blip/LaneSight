import SwiftUI

// MARK: - LaneSight visual language (HANDOFF §5)
//
// Dark navy surfaces, blue/cyan accents, and the three metric-status colors. These are the single
// source of truth for color in the app; no screen hardcodes hex values of its own.

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

enum LS {
    // Surfaces
    static let bg = Color(hex: 0x060C1C)        // app background
    static let bgAuth = Color(hex: 0x020A14)    // auth / onboarding background
    static let card = Color(hex: 0x0D1830)      // card fill
    static let cardStroke = Color.white.opacity(0.06)

    // Accents
    static let blue = Color(hex: 0x2F7DFF)
    static let cyan = Color(hex: 0x38C6F4)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textFaint = Color.white.opacity(0.38)

    // Metric-status colors (status never shown by color alone — always paired with a label)
    static let measured = Color(hex: 0x3DDC97)
    static let bestEffort = Color(hex: 0xFFB547)
    static let unavailable = Color.white.opacity(0.35)
}

// MARK: - Metric status

/// Normalizes the server's free-form status strings into the three displayed states.
enum MetricStatus {
    case measured, bestEffort, unavailable

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "ok", "measured", "good": self = .measured
        case "best_effort", "watch", "degraded": self = .bestEffort
        default: self = .unavailable
        }
    }

    var label: String {
        switch self {
        case .measured: return "Measured"
        case .bestEffort: return "Best effort"
        case .unavailable: return "Unavailable"
        }
    }

    var color: Color {
        switch self {
        case .measured: return LS.measured
        case .bestEffort: return LS.bestEffort
        case .unavailable: return LS.unavailable
        }
    }

    var symbol: String {
        switch self {
        case .measured: return "circle.fill"
        case .bestEffort: return "circle.lefthalf.filled"
        case .unavailable: return "circle"
        }
    }
}

// MARK: - Reusable card container

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LS.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LS.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func lsCard(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Section eyebrow label used throughout the designs (e.g. "SCORE BREAKDOWN").
    func lsEyebrow() -> some View {
        self.font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(LS.textSecondary)
    }
}

/// A screen-filling dark background that respects the design's navy surface.
struct LSBackground: View {
    var auth = false
    var body: some View {
        (auth ? LS.bgAuth : LS.bg).ignoresSafeArea()
    }
}

/// "Coming soon" / honest-empty placeholder used by not-yet-backed screens and disabled tiles.
struct ComingSoonView: View {
    let title: String
    var message: String
    var symbol: String = "hourglass"

    init(_ title: String, message: String = "This is coming soon. It isn't available in this dev build yet.", symbol: String = "hourglass") {
        self.title = title
        self.message = message
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(LS.cyan)
            Text(title).font(.title3.bold()).foregroundStyle(LS.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(LSBackground())
    }
}
