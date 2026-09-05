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
    /// The sans, for everything the app draws itself.
    public static let sans = "Geist"
    /// The mono, for the terminal. A terminal lays out on a character cell, so
    /// this half cannot be the sans no matter how much nicer it looks.
    public static let mono = "Geist Mono"

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
