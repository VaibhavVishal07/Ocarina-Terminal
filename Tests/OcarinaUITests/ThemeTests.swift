import AppKit
import Testing
@testable import OcarinaUI

@MainActor
@Suite("Themes")
struct ThemeTests {

    private var bundled: [Theme] {
        // The store filters unusable themes out, which is exactly what must not
        // happen silently for a theme we ship — so read the files directly.
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Themes") ?? []
        let decoder = JSONDecoder()
        return urls.compactMap { try? decoder.decode(Theme.self, from: Data(contentsOf: $0)) }
    }

    @Test("Every bundled theme is on disk and parses")
    func themesLoad() throws {
        let themes = bundled
        #expect(themes.count >= 14)
        #expect(Set(themes.map(\.id)).count == themes.count, "theme ids must be unique")
    }

    @Test("No bundled theme can make terminal text unreadable")
    func contrastFloor() throws {
        for theme in bundled {
            let report = ThemeReport(theme: theme)
            #expect(
                report.isUsable,
                """
                \(theme.id) fails the contrast floor: \
                \(report.unreadable.map { "\($0.what) \(String(format: "%.2f", $0.ratio)):1" }
                    .joined(separator: ", "))
                """
            )
        }
    }

    @Test("Every bundled theme is a dark theme")
    func allDark() {
        // A terminal is looked at for hours in a dim room; a light one is a
        // lamp. Sakura is dark pink rather than pale pink for that reason, not
        // because pink was the problem.
        for theme in bundled {
            #expect(theme.isDark, "\(theme.id) is not dark")
            #expect(
                theme.terminal.background.luminance < 0.06,
                "\(theme.id) background is too bright to call dark"
            )
        }
    }

    @Test("You can see what you have selected")
    func selectionIsVisible() {
        // Selection was a barely-tinted wash — Sakura's was 1.27:1 against its
        // own background, so dragging over text showed almost nothing. It has
        // to separate from the page and still let the text on it be read.
        for theme in bundled {
            let terminal = theme.terminal
            let againstPage = terminal.selection.contrast(against: terminal.background)
            let textOnIt = terminal.foreground.contrast(against: terminal.selection)
            #expect(againstPage >= 2.0, "\(theme.id) selection is invisible (\(againstPage))")
            #expect(textOnIt >= 4.5, "\(theme.id) text on selection is unreadable (\(textOnIt))")
        }
    }

    @Test("The bundled typeface is there and the mono half is monospaced")
    func geistIsBundled() {
        BundledFonts.register()
        #expect(BundledFonts.areAvailable, "Geist did not register from the bundle")
        // The half that matters most: a proportional face in a terminal does
        // not look wrong, it tears — every column after the first drifts.
        #expect(NSFont(name: BundledFonts.mono, size: 13)?.isFixedPitch == true)
        #expect(NSFont(name: BundledFonts.sans, size: 13)?.isFixedPitch == false)
    }

    @Test("Every theme sets its terminal in the bundled mono")
    func themesUseGeist() {
        // Every theme used to name "SF Mono", which does not resolve under that
        // name on macOS — so all of them silently fell back and the files
        // described a font nobody ever saw. Geist ships with the app, so the
        // name in the file is the face on the screen.
        BundledFonts.register()
        for theme in bundled {
            #expect(theme.terminal.fontName == BundledFonts.mono, "\(theme.id)")
            #expect(theme.terminal.fontIsUsable, "\(theme.id) cannot resolve its font")
        }
    }

    @Test("Chrome falls through to the bundled sans")
    func chromeUsesGeist() {
        BundledFonts.register()
        for theme in bundled {
            // No bundled theme overrides it; a user theme still may.
            #expect(theme.typography?.uiFontName == nil, "\(theme.id) overrides the app face")
        }
    }

    @Test("A terminal needs all sixteen colours to index into")
    func sixteenColours() throws {
        for theme in bundled {
            #expect(theme.terminal.ansi.count == 16, "\(theme.id) has \(theme.terminal.ansi.count)")
        }
    }

    @Test("A proportional font falls back rather than tearing the grid")
    func fontFallback() {
        let proportional = Theme.Terminal(
            background: ThemeColor(hex: "#000000"),
            foreground: ThemeColor(hex: "#FFFFFF"),
            cursor: ThemeColor(hex: "#FFFFFF"),
            selection: ThemeColor(hex: "#333333"),
            ansi: Array(repeating: ThemeColor(hex: "#FFFFFF"), count: 16),
            fontName: "Helvetica",
            fontSize: 13
        )
        #expect(proportional.fontIsUsable == false)
        #expect(proportional.resolvedFont.isFixedPitch, "fell back to something monospaced")
    }

    @Test("A colour that is not a colour does not stop the app opening")
    func malformedColour() {
        let grey = ThemeColor(hex: "not a colour")
        #expect(grey.red == 0.5 && grey.green == 0.5 && grey.blue == 0.5)
    }

    @Test("Contrast is computed the way WCAG defines it")
    func contrastMaths() {
        let black = ThemeColor(hex: "#000000")
        let white = ThemeColor(hex: "#FFFFFF")
        #expect(abs(white.contrast(against: black) - 21) < 0.01)
        #expect(abs(white.contrast(against: white) - 1) < 0.01)
    }

    @Test("A fresh install opens in the house theme, not the first file")
    func defaultTheme() {
        UserDefaults.standard.removeObject(forKey: "ocarina.theme")
        #expect(ThemeStore().theme.id == "ocarina")
    }

    @Test("There is always a theme, even with nothing on disk")
    func alwaysATheme() {
        #expect(ThemeReport(theme: .fallback).isUsable)
    }
}
