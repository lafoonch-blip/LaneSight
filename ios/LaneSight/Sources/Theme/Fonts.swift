import SwiftUI
import UIKit

// MARK: - Roboto Condensed (bundled) — app-wide type (design README 3.0 / Figma "01 - Design Standards")
//
// Two static instances are bundled (generated from the OFL variable font): Regular (400) and
// SemiBold (600). SwiftUI weights are mapped onto those two faces so weight requests are honored
// deterministically by picking the exact bundled face — never a synthetic bold and never a system
// fallback. The family ("Roboto Condensed") carries both faces so `.weight()`/`.bold()` chains and
// Dynamic Type both resolve correctly.

enum LSFont {
    static let family = "Roboto Condensed"
    static let regular = "RobotoCondensed-Regular"
    static let semibold = "RobotoCondensed-SemiBold"

    /// Map any SwiftUI weight onto one of the two bundled faces (400 or 600).
    static func psName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: return semibold
        default: return regular
        }
    }

    static func uiWeight(for weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: return .semibold
        default: return .regular
        }
    }

    /// True once the bundled faces are registered (both must be present).
    static var isRegistered: Bool {
        let names = Set(UIFont.fontNames(forFamilyName: family))
        return names.contains(regular) && names.contains(semibold)
    }
}

extension Font {
    /// Roboto Condensed at an explicit size + weight, scaling with Dynamic Type relative to `textStyle`.
    /// Picks the exact bundled face for the weight, so 400/600 render distinctly.
    static func lsRoboto(_ size: CGFloat, weight: Font.Weight = .regular,
                         relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(LSFont.psName(for: weight), size: size, relativeTo: textStyle)
    }

    // Semantic styles mirroring SwiftUI's text styles, in Roboto Condensed. Sizes track Apple's
    // default point sizes; weights follow the platform convention (headline = semibold). Use these
    // in place of `.title`, `.headline`, `.body`, … so the whole app renders in Roboto Condensed.
    static var lsLargeTitle: Font { lsRoboto(34, weight: .regular,  relativeTo: .largeTitle) }
    static var lsTitle: Font      { lsRoboto(28, weight: .regular,  relativeTo: .title) }
    static var lsTitle2: Font     { lsRoboto(22, weight: .regular,  relativeTo: .title2) }
    static var lsTitle3: Font     { lsRoboto(20, weight: .regular,  relativeTo: .title3) }
    static var lsHeadline: Font   { lsRoboto(17, weight: .semibold, relativeTo: .headline) }
    static var lsBody: Font       { lsRoboto(17, weight: .regular,  relativeTo: .body) }
    static var lsCallout: Font    { lsRoboto(16, weight: .regular,  relativeTo: .callout) }
    static var lsSubheadline: Font { lsRoboto(15, weight: .regular, relativeTo: .subheadline) }
    static var lsFootnote: Font   { lsRoboto(13, weight: .regular,  relativeTo: .footnote) }
    static var lsCaption: Font    { lsRoboto(13, weight: .regular,  relativeTo: .caption) }   // 13px min (3.0)
    static var lsCaption2: Font   { lsRoboto(13, weight: .regular,  relativeTo: .caption2) }  // 13px min (3.0)
}

// MARK: - App-wide default

extension View {
    /// Sets the default app font to Roboto Condensed body. Views using the `.ls*` styles override
    /// this with the right size/weight; anything that doesn't set a font still renders in Roboto.
    func lsAppFont() -> some View { self.font(.lsBody) }
}

// MARK: - UIKit chrome appearance (tab bar + nav bar) in Roboto Condensed + 3.0 palette

enum LSAppearance {
    static func apply() {
        let regular = UIFont(name: LSFont.regular, size: 10) ?? .systemFont(ofSize: 10)
        let selected = UIFont(name: LSFont.semibold, size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)

        // Tab bar (3.0): dark card surface, cyan selected, muted unselected, Roboto labels.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(LS.card)
        tab.shadowColor = UIColor(LS.border)
        func style(_ item: UITabBarItemAppearance) {
            item.normal.iconColor = UIColor(LS.textSecondary)
            item.normal.titleTextAttributes = [
                .foregroundColor: UIColor(LS.textSecondary), .font: regular]
            item.selected.iconColor = UIColor(LS.action)
            item.selected.titleTextAttributes = [
                .foregroundColor: UIColor(LS.action), .font: selected]
            // Disabled (Leagues/Tourneys) read as dimmed, not tappable-looking.
            item.disabled.iconColor = UIColor(LS.textSecondary).withAlphaComponent(0.35)
            item.disabled.titleTextAttributes = [
                .foregroundColor: UIColor(LS.textSecondary).withAlphaComponent(0.35), .font: regular]
        }
        style(tab.stackedLayoutAppearance)
        style(tab.inlineLayoutAppearance)
        style(tab.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Nav bar: dark canvas, Roboto titles, light text.
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(LS.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(LS.textPrimary),
            .font: UIFont(name: LSFont.semibold, size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(LS.textPrimary),
            .font: UIFont(name: LSFont.semibold, size: 34) ?? .systemFont(ofSize: 34, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // Bar buttons in Roboto.
        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: UIFont(name: LSFont.regular, size: 17) ?? .systemFont(ofSize: 17)], for: .normal)
    }
}

#if DEBUG
enum LSFontCheck {
    /// Logged once at launch so we can confirm the bundled faces actually registered (not a fallback).
    static func log() {
        let names = UIFont.fontNames(forFamilyName: LSFont.family)
        print("‼️ LSFont registered faces for \(LSFont.family): \(names) | isRegistered=\(LSFont.isRegistered)")
    }
}
#endif
