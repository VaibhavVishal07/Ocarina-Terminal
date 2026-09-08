import AppKit
import SwiftUI
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

    @Test("A lattice, where there is one, stays behind the text")
    func patterns() {
        for theme in bundled {
            guard let motif = theme.pattern else { continue }
            // Above about 0.07 it stops being texture and starts competing
            // with the text in front of it.
            #expect(motif.opacity > 0 && motif.opacity <= 0.07,
                    "\(theme.id) motif opacity \(motif.opacity)")
            #expect(motif.scale >= 2 && motif.scale <= 40)
        }
    }

    @Test("Every theme has a surface of its own, and High Contrast has none")
    func everyThemeHasATexture() {
        // The point of bringing these back: a theme is a material as well as
        // a palette, and thirteen of the fourteen say what they are made of.
        // Somebody who turned contrast up did not ask for wallpaper, so the
        // fourteenth is plain on purpose rather than by omission.
        let plain = bundled.filter { $0.pattern == nil }.map(\.id)
        #expect(plain == ["high-contrast"], "unexpectedly plain: \(plain)")

        // And no two themes wear the same one, or the surface stops telling
        // you which theme you are in.
        let shapes = bundled.compactMap { $0.pattern?.shape }
        #expect(Set(shapes).count == shapes.count, "two themes share a motif")
    }

    @Test("Every lattice actually draws something")
    func everyLatticeDraws() {
        // A pattern that builds an empty path is a theme with no surface that
        // still claims one — and at 0.05 opacity nobody would ever notice.
        let panel = CGSize(width: 230, height: 400)
        for shape in Motif.Shape.allCases where shape != .brushed {
            let (stroked, filled) = PatternView.paths(for: shape, size: panel, step: 12)
            #expect(!stroked.isEmpty || !filled.isEmpty, "\(shape) draws nothing")

            // And it has to cover the panel rather than sitting in a corner:
            // every lattice runs a cell past all four edges on purpose.
            let bounds = stroked.isEmpty ? filled.boundingRect
                                         : stroked.boundingRect.union(filled.boundingRect)
            #expect(bounds.width >= panel.width * 0.9, "\(shape) leaves a bare edge")
            #expect(bounds.height >= panel.height * 0.9, "\(shape) leaves a bare edge")
        }
    }

    @Test("A lattice is ruled to its period, not scattered")
    func latticesAreRegular() {
        // The whole reason the old motifs went: a scatter has marks to find,
        // and a lattice has none. Two panels of the same size draw the same
        // path, and a panel twice as tall draws more of it rather than a
        // different arrangement of it.
        let short = PatternView.paths(for: .diamonds, size: CGSize(width: 200, height: 100), step: 12)
        let same = PatternView.paths(for: .diamonds, size: CGSize(width: 200, height: 100), step: 12)
        #expect(short.1.description == same.1.description)

        let tall = PatternView.paths(for: .diamonds, size: CGSize(width: 200, height: 200), step: 12)
        #expect(tall.1.description.hasPrefix(short.1.description))
    }

    @Test("A hexagon closes, and is as wide as a pointy-top cell should be")
    func honeycomb() {
        let cell = PatternView.hexagon(at: CGPoint(x: 0, y: 0), radius: 10)
        let bounds = cell.boundingRect
        // Pointy-top: two radii tall, `radius * sqrt(3)` across.
        #expect(abs(bounds.height - 20) < 0.01)
        #expect(abs(bounds.width - 10 * sqrt(3.0)) < 0.01)
    }

    @Test("The bundled typeface is there and the mono half is monospaced")
    func facesAreBundled() {
        BundledFonts.register()
        #expect(BundledFonts.areAvailable, "the bundled faces did not register")
        // The half that matters most: a proportional face in a terminal does
        // not look wrong, it tears — every column after the first drifts.
        #expect(NSFont(name: BundledFonts.mono, size: 13)?.isFixedPitch == true)
        #expect(NSFont(name: BundledFonts.sans, size: 13)?.isFixedPitch == false)
    }

    @Test("The interface face is Geist, and its weights are distinct")
    func geistCarriesItsWeights() {
        BundledFonts.register()
        #expect(BundledFonts.sans == "Geist")

        // The one that is worth a test. The chrome leans on weight to
        // separate a label from its value — "This window" against "1.4M" —
        // and a family that answers to its name while resolving every weight
        // to the same face passes every other check in this file while
        // flattening the whole app. It happens: the variable file's own
        // PostScript names all read as Bold, and a descriptor built the
        // wrong way returns one instance for all six.
        let sample = "Something is building" as NSString
        var widths: [Double] = []
        for weight: NSFont.Weight in [.light, .regular, .medium, .bold, .black] {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: BundledFonts.sans,
                .traits: [NSFontDescriptor.TraitKey.weight: weight],
            ])
            let font = try! #require(NSFont(descriptor: descriptor, size: 13))
            widths.append(sample.size(withAttributes: [.font: font]).width)
        }
        // Strictly increasing: heavier is wider, in this face at this size.
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == widths.count, "the weights collapse to one face")
    }

    @Test("Every theme sets its terminal in the bundled mono")
    func themesUseTheBundledMono() {
        // Every theme used to name "SF Mono", which does not resolve under that
        // name on macOS — so all of them silently fell back and the files
        // described a font nobody ever saw. JetBrains Mono ships with the app,
        // so the name in the file is the face on the screen.
        BundledFonts.register()
        for theme in bundled {
            #expect(theme.terminal.fontName == BundledFonts.mono, "\(theme.id)")
            #expect(theme.terminal.fontIsUsable, "\(theme.id) cannot resolve its font")
        }
    }

    @Test("Every theme sets the chrome in the one bundled face")
    func chromeFaces() {
        // A theme could name its own typeface for a while, and the result was
        // fourteen apps rather than one app in fourteen colours — Georgia and
        // Futura are different objects before you have read a word of either.
        // The face is Geist for everyone now, and the point of this test
        // is that no theme can quietly get that option back.
        BundledFonts.register()
        let house = Font.custom(BundledFonts.ui, fixedSize: 12).weight(.regular)
        for theme in bundled where theme.shape.weight == .regular {
            #expect(theme.uiFont(12) == house, "\(theme.id) is not in the app face")
        }
    }

    @Test("Every bundled theme has something to say for itself")
    func everyThemeSpeaks() {
        for theme in bundled {
            let speech = theme.speech
            for (what, line) in [
                ("working", speech.working), ("done", speech.done),
                ("stopped", speech.stopped), ("clear", speech.clear),
            ] {
                #expect(!line.isEmpty, "\(theme.id) has no \(what) line")
                // It goes in the menu bar, which is the most expensive strip of
                // screen on the Mac. A theme is welcome to a voice; it is not
                // welcome to a sentence up there.
                #expect(line.count <= 24, "\(theme.id)'s \(what) line is \(line.count) characters")
            }
            #expect(theme.speech.blurb?.isEmpty == false, "\(theme.id) has no blurb for the picker")
        }
    }

    @Test("No two themes say the same thing in the same words")
    func voicesDiffer() {
        // The point of the field. Fourteen themes reading as one app with the
        // hue turned is exactly what this exists to stop, so two of them
        // sharing a whole vocabulary is a copy-paste, not a decision.
        let voices = bundled.map { theme in
            [theme.speech.working, theme.speech.done, theme.speech.stopped, theme.speech.clear]
        }
        #expect(Set(voices.map { $0.joined(separator: "|") }).count == voices.count)
    }

    @Test("A theme that says nothing about its feel looks exactly as it did")
    func textureDefaults() {
        // The same rule the colour layer follows: a field nobody filled in
        // gets the number that was compiled in before the field existed, so
        // adding the field changed no theme that did not ask to change.
        let house = Theme.fallback.shape
        #expect(house.sheen == Theme.Shape.houseSheen)
        #expect(house.bloom == Theme.Shape.houseBloom)
        #expect(house.caret == .bar)
        #expect(house.weight == .regular)
    }

    @Test("A texture nobody can read costs that one field, not the app")
    func textureFallsBack() {
        let nonsense = Theme.Shape.Caret(named: "sideways")
        #expect(nonsense == .bar)
        #expect(Theme.Shape.Caret(named: nil) == .bar)
        #expect(Theme.Shape.Caret(named: "BLOCK") == .block, "a name is matched case-insensitively")
        #expect(Theme.Shape.Weight(named: "enormous") == .regular)
    }

    @Test("A theme's weight shift moves one step and stops at the ends")
    func weightShiftClamps() {
        func shape(_ weight: String) -> Theme.Shape {
            Theme.Shape(
                caret: .bar, sheen: 0.035, bloom: 1,
                weight: Theme.Shape.Weight(named: weight)
            )
        }
        #expect(shape("heavy").shift(.medium) == .semibold)
        #expect(shape("light").shift(.medium) == .regular)
        #expect(shape("regular").shift(.medium) == .medium)
        // The ends clamp rather than wrapping round to the other extreme.
        #expect(shape("light").shift(.ultraLight) == .ultraLight)
        #expect(shape("heavy").shift(.black) == .black)
    }

    @Test("Themes differ in feel and not only in hue")
    func texturesDiffer() {
        // Steel is lit flat; Sakura blooms. If every theme resolved to the
        // same numbers the field would be decoration on a JSON file. The cut
        // is not among them any more — every panel takes the house radius.
        let steel = bundled.first { $0.id == "steel" }?.shape
        let sakura = bundled.first { $0.id == "sakura" }?.shape
        #expect((steel?.bloom ?? 1) < (sakura?.bloom ?? 0))
        #expect(steel?.weight == .heavy)
        #expect(sakura?.weight == .light)
        // Matrix is the one that wants the block back: it is a theme about
        // terminals rather than about a colour.
        #expect(bundled.first { $0.id == "matrix" }?.shape.caret == .block)
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

    @Test("The compiled-in theme still says what its file says")
    func fallbackMatchesItsFile() throws {
        // `Theme.fallback` duplicates ocarina.json on purpose — it is what
        // applies when resource loading has already failed, so it cannot
        // itself depend on a resource loading. Duplication that nothing
        // checks is duplication that drifts, and the voice drifted the day it
        // was added: the file said one thing and the compiled copy another.
        let file = try #require(bundled.first { $0.id == "ocarina" })
        #expect(file.speech == Theme.fallback.speech)
        #expect(file.shape == Theme.fallback.shape)
    }

    @Test("There is always a theme, even with nothing on disk")
    func alwaysATheme() {
        #expect(ThemeReport(theme: .fallback).isUsable)
    }
}

@Suite("The column's fall")
@MainActor
struct PanelFallTests {

    private let theme = Theme.fallback

    /// The gradient stops a place is drawn between, as hex, so a fall can be
    /// checked without rendering anything.
    private func run(_ place: OcarinaWindowView.PanelPlace) -> (String, String) {
        let handover = theme.chrome.panelBottom.mixed(with: theme.ground, by: 0.5)
        return switch place {
        case .top:    (theme.chrome.panelTop.hex, theme.chrome.panelBottom.hex)
        case .bottom: (theme.chrome.panelBottom.hex, theme.ground.hex)
        case .middle: (theme.chrome.panelBottom.hex, handover.hex)
        case .foot:   (handover.hex, theme.ground.hex)
        }
    }

    @Test("A mix lands between the two colours it was given")
    func mixInterpolates() {
        let black = ThemeColor(hex: "#000000")
        let white = ThemeColor(hex: "#FFFFFF")
        #expect(black.mixed(with: white, by: 0).hex == "#000000")
        #expect(black.mixed(with: white, by: 1).hex == "#FFFFFF")
        #expect(black.mixed(with: white, by: 0.5).hex == "#808080")
        // Out of range is clamped rather than allowed to overshoot into a
        // colour neither stop contains.
        #expect(black.mixed(with: white, by: 2).hex == "#FFFFFF")
        #expect(black.mixed(with: white, by: -1).hex == "#000000")
    }

    @Test("A stack of three hands over where a stack of two crosses")
    func threeCardsMeetTwo() {
        // The whole point of `.middle` and `.foot`: one fall cut into three
        // pieces rather than a second fall starting halfway down the column.
        // Where the second card stops is where the third begins.
        #expect(run(.middle).1 == run(.foot).0)
        // And the ends are the same as a two-card column's ends, so the two
        // depths of column start and finish together.
        #expect(run(.top).0 == theme.chrome.panelTop.hex)
        #expect(run(.foot).1 == run(.bottom).1)
        #expect(run(.middle).0 == run(.bottom).0)
    }

    @Test("Only the head of a stack catches the light")
    func sheenIsTopOnly() {
        // A card halfway down a falling gradient has no reason to catch light
        // of its own, and putting one there is what made the second card glow
        // in the middle of a fall. Adding two places to the enum must not have
        // lit either of them.
        #expect(OcarinaWindowView.catchesLight(.top))
        for place in [OcarinaWindowView.PanelPlace.bottom, .middle, .foot] {
            #expect(!OcarinaWindowView.catchesLight(place))
        }
    }
}
