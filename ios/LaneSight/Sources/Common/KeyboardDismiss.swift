import SwiftUI
import UIKit

/// Global keyboard dismissal: a window-wide tap recognizer that ends editing on any tap outside a text
/// field. `cancelsTouchesInView = false` so it never swallows button/row taps. Installed once at the app
/// root via `.installGlobalKeyboardDismiss()`; a single UIWindow backs the app (sheets included), so this
/// covers every screen where previously the keyboard had no way down.
private final class KeyboardDismissHostView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        if window.gestureRecognizers?.contains(where: { $0 is KeyboardDismissTap }) == true { return }
        let tap = KeyboardDismissTap(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = Self.shared
        window.addGestureRecognizer(tap)
    }
    @objc private func dismissKeyboard() { window?.endEditing(true) }
    private static let shared = GestureDelegate()
}

/// Marker subclass so we don't install the recognizer twice on the same window.
private final class KeyboardDismissTap: UITapGestureRecognizer {}

/// Lets the tap recognize simultaneously with everything else (buttons, scrolling, other taps).
private final class GestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { KeyboardDismissHostView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Install the global tap-to-dismiss-keyboard behavior. Apply once at the app root.
    func installGlobalKeyboardDismiss() -> some View {
        background(KeyboardDismissInstaller().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
