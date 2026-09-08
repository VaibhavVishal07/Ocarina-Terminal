import AppKit
import CoreText

/// Makes the app's own typeface available to the app.
///
/// Both faces ship with Ocarina rather than being looked up on the machine.
/// Neither is a system face, so relying on the user having installed one means
/// the app looks different depending on who opens it — and the fallback,
/// whatever it happened to be, would never be the design. Two variable fonts,
/// 461KB, both under the SIL Open Font License — one licence file each,
/// because they come from different projects and each carries its own
/// copyright line, and both sit beside the fonts in the bundle.
public enum BundledFonts {
    /// Geist. Everything the app draws itself is set in this.
    ///
    /// The family name, which here is also the file name: Geist's variable
    /// file registers its family as plain *Geist*, covering the whole 100–900
    /// axis under the one name.
    public static let sans = "Geist"

    /// JetBrains Mono, and only for the terminal.
    ///
    /// Not a style choice: a terminal lays out on a fixed character cell, and
    /// a proportional face does not look wrong there, it tears — every column
    /// after the first drifts and box-drawing, tables and aligned output come
    /// apart. The sans cannot do this job however much better it reads.
    ///
    /// The roman file only. Terminal italics are rare enough, and synthesised
    /// slant holds the cell where a separate italic file would be another
    /// 300KB for the odd `ls` colour.
    public static let mono = "JetBrains Mono"

    /// What the app draws its own chrome in.
    public static var ui: String { sans }

    @MainActor private static var registered = false

    /// Called once, before any window is built.
    @MainActor
    public static func register() {
        guard !registered else { return }
        registered = true

        // File names, which for the mono is not the family name: the file
        // ships as `JetBrainsMono[wght].ttf` and is stored here without the
        // axis suffix, since the bundle looks it up by name.
        for name in ["Geist", "JetBrainsMono"] {
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
