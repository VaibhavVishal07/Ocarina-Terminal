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
    /// Geist. Everything the app draws itself is set in this.
    public static let sans = "Geist"

    /// Geist Mono, and only for the terminal.
    ///
    /// Not a style choice: a terminal lays out on a fixed character cell, and
    /// a proportional face does not look wrong there, it tears — every column
    /// after the first drifts and box-drawing, tables and aligned output come
    /// apart. The sans cannot do this job however much better it reads.
    public static let mono = "Geist Mono"

    /// What the app draws its own chrome in.
    public static var ui: String { sans }

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
