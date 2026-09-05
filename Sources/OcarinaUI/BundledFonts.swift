import AppKit
import CoreText

/// Makes the app's own typeface available to the app.
///
/// Geist ships with Ocarina rather than being looked up on the machine. It is
/// not a system face, so relying on the user having installed it means the app
/// looks different depending on who opens it — and the fallback, whatever it
/// happened to be, would never be the design. Two variable fonts, 330KB, under
/// the SIL Open Font License, whose text sits beside them in the bundle.
public enum BundledFonts {
    /// The mono. The terminal has no choice — it lays out on a character cell
    /// — and the chrome is set in it too, so the app wears one face rather
    /// than a pair that have to be kept in agreement.
    public static let mono = "Geist Mono"

    /// What the app draws its own chrome in.
    public static var ui: String { mono }

    /// The sans. Bundled but unused: it is the obvious alternative if an
    /// all-monospace interface wears thin, and 165KB is cheaper than going
    /// and fetching it again.
    public static let sans = "Geist"

    @MainActor private static var registered = false

    /// Called once, before any window is built.
    @MainActor
    public static func register() {
        guard !registered else { return }
        registered = true

        for name in ["Geist", "GeistMono"] {
            guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "ttf",
                subdirectory: "Fonts"
            ) else { continue }
            // Process scope: the font is this app's, not installed for the
            // machine. Nothing is left behind when Ocarina quits.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Whether both faces resolved. Used by the tests, and worth knowing:
    /// silently falling back is how every theme ended up naming "SF Mono", a
    /// font that does not exist under that name.
    public static var areAvailable: Bool {
        NSFont(name: sans, size: 12) != nil && NSFont(name: mono, size: 12)?.isFixedPitch == true
    }
}
