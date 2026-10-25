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

// MARK: - 3.0 color palette (Figma "01 - Design Standards", design README 3.0)
//
// Token NAMES are kept stable so every screen keeps compiling; the hex VALUES are the 3.0 palette.
// Legacy accent names (`blue`, `cyan`) now resolve to the single action color; `measured` resolves to
// `success`; `cardStroke` resolves to the standard border. A full per-screen restyle lands in a later
// step — here we establish the tokens and apply them on the brand screens.
enum LS {
    // Surfaces
    static let bg = Color(hex: 0x001018)            // canvas / app background
    static let bgAuth = Color(hex: 0x001018)        // auth uses the same canvas in 3.0
    static let card = Color(hex: 0x031B29)          // card fill
    static let raised = Color(hex: 0x062132)        // raised surface (e.g. score card)
    static let selected = Color(hex: 0x0C2B40)      // selected / standard border fill
    static let border = Color(hex: 0x0C2B40)        // standard 1px border
    static let borderStrong = Color(hex: 0x153B51)  // strong border (inputs, raised cards)
    static let cardStroke = Color(hex: 0x0C2B40)    // legacy name → standard border

    // Accent / action
    static let action = Color(hex: 0x00A8F5)        // primary action (cyan)
    static let onAction = Color(hex: 0x001018)      // text / icon on an action surface
    static let blue = Color(hex: 0x00A8F5)          // legacy name → action
    static let cyan = Color(hex: 0x00A8F5)          // legacy name → action

    // Text
    static let textPrimary = Color(hex: 0xF5F6FA)
    static let textSecondary = Color(hex: 0xBFCBDD)
    static let textFaint = Color(hex: 0xBFCBDD).opacity(0.6)

    // Success (positive deltas / "Measured" status)
    static let success = Color(hex: 0x00EB92)
    static let successBg = Color(hex: 0x003D28)
    static let measured = Color(hex: 0x00EB92)      // legacy metric-status name → success

    // Data-only colors (charts / score breakdown). Never used for status or chrome.
    static let dataPurple = Color(hex: 0xA55ED0)
    static let dataYellow = Color(hex: 0xF5CD31)
    static let dataOrange = Color(hex: 0xFA923C)

    // Metric-status helpers kept so existing screens compile (full restyle later). There is no error
    // color in v1 — failures use neutral surfaces + plain text.
    static let bestEffort = Color(hex: 0xF5CD31)    // amber attention (data-yellow hue)
    static let unavailable = Color(hex: 0xBFCBDD).opacity(0.5)
}

// MARK: - Metric status

/// Normalizes the server's free-form status strings into the three displayed states. This is the ONE
/// status mapping used everywhere (ball + form); it matches the design's three-chip rule exactly
/// (NextShotStates.dc.html "METRIC STATUS"): MEASURED = ok/measured; BEST EFFORT = best_effort /
/// low_confidence / calibrated_estimate (value shown rounded, with ± band when known); UNAVAILABLE =
/// unavailable or anything else (never shows a number — shows the reason). The previous mapping let
/// low_confidence / calibrated_estimate fall through to UNAVAILABLE while still showing a value
/// (SHOT_REVIEW 2026-10-25); they are estimates and belong in BEST EFFORT.
enum MetricStatus {
    case measured, bestEffort, unavailable

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "ok", "measured", "good": self = .measured
        case "best_effort", "low_confidence", "calibrated_estimate", "estimate", "watch", "degraded": self = .bestEffort
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
            .background(LS.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LS.border, lineWidth: 1)
            )
    }
}

extension View {
    func lsCard(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Section eyebrow label used throughout the designs (e.g. "SCORE BREAKDOWN").
    func lsEyebrow() -> some View {
        self.font(.lsCaption.weight(.semibold))
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
            Text(title).font(.lsTitle3.bold()).foregroundStyle(LS.textPrimary)
            Text(message)
                .font(.lsCallout)
                .foregroundStyle(LS.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(LSBackground())
    }
}
