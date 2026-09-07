import AppKit
import CoreText

/// Makes the app's own typeface available to the app.
///
/// Both faces ship with Ocarina rather than being looked up on the machine.
/// Neither is a system face, so relying on the user having installed one means
/// the app looks different depending on who opens it — and the fallback,
/// whatever it happened to be, would never be the design. Two variable fonts,
/// 291KB, and both licences sit beside them in the bundle: Geist Mono under
/// the SIL Open Font License, Satoshi under the ITF Free Font License, which
/// permits embedding in a desktop application and forbids altering the file —
/// so it ships unsubsetted, unconverted and under its own name.
public enum BundledFonts {
    /// Satoshi. Everything the app draws itself is set in this.
    ///
    /// The family name, not the file name, and not "Satoshi": the file that
    /// ships is the variable one, and it registers its family as *Satoshi
    /// Variable*. The static OTFs are the ones that answer to "Satoshi", and
    /// they are five files to this one's coverage of the same five weights.
    public static let sans = "Satoshi Variable"

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

        // File names, which are not the family names above — Satoshi's file
        // keeps the name the foundry shipped it under, because the licence
        // does not allow renaming it.
        for name in ["Satoshi-Variable", "GeistMono"] {
            guard let url = PackagedResources.bundle.url(
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
