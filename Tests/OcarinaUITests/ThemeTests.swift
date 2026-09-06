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

    @Test("Body text is white with a tinge of the theme, never the theme itself")
    func textCarriesOnlyATinge() {
        func chroma(_ colour: ThemeColor) -> Double {
            max(colour.red, colour.green, colour.blue) - min(colour.red, colour.green, colour.blue)
        }
        for theme in bundled {
            let terminal = theme.terminal
            // The slack is one 8-bit step: the cap is applied in floating
            // point and written back as three bytes.
            #expect(
                chroma(terminal.text) <= Theme.Terminal.textChroma + 1.0 / 255,
                "\(theme.id) sets its text in the theme's colour rather than in white wearing it"
            )
            // The two whites are the text colour in every bundled theme, so
            // they answer to the same ceiling — capping one and not the other
            // leaves a program printing in white louder than the line above it.
            #expect(chroma(terminal.palette[7]) <= Theme.Terminal.textChroma + 1.0 / 255)
            #expect(chroma(terminal.palette[15]) <= Theme.Terminal.textChroma + 1.0 / 255)
        }
    }

    @Test("A theme already written that quietly is left exactly as it is")
    func quietThemesAreUntouched() throws {
        // The ceiling takes the loud ones down to where the quiet ones already
        // sit. Thirteen of the fourteen were already there, and a rule that
        // rewrote them too would be redecorating somebody's theme.
        let untouched = try #require(bundled.first { $0.id == "ocarina" }).terminal
        #expect(untouched.text == untouched.foreground)
        #expect(untouched.palette == untouched.ansi)

        let loud = try #require(bundled.first { $0.id == "matrix" }).terminal
        #expect(loud.text != loud.foreground)
        // And it stays as light as it was authored: pulled towards the grey of
        // its own luminance, not towards the midpoint of its channels.
        #expect(abs(loud.text.luminanceLevel - loud.foreground.luminanceLevel) < 0.01)
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
