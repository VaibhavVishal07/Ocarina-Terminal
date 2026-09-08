import AppKit
import SwiftTerm
import SwiftUI

/// A colour written the way a theme file writes it: `"#38C2FF"`.
///
/// Themes are authored by hand, including by people who are not going to
/// compile anything, so the wire format is a hex string rather than a struct of
/// floats. Everything downstream — SwiftUI, AppKit, SwiftTerm — wants a
/// different colour type, so the conversions live here rather than at each
/// call site.
public struct ThemeColor: Codable, Sendable, Equatable, Hashable {
    public let hex: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: String) {
        self.hex = hex
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        // A malformed colour resolves to mid-grey rather than throwing. A
        // typo in one swatch of a user's theme should not stop the app from
        // opening — the contrast report will point at it.
        guard value.count == 6, let packed = UInt32(value, radix: 16) else {
            red = 0.5; green = 0.5; blue = 0.5
            return
        }
        red = Double((packed >> 16) & 0xFF) / 255
        green = Double((packed >> 8) & 0xFF) / 255
        blue = Double(packed & 0xFF) / 255
    }

    public init(from decoder: Decoder) throws {
        self.init(hex: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// Qualified: SwiftTerm exports a `Color` of its own, and this file has to
    /// speak to both.
    public var color: SwiftUI.Color { SwiftUI.Color(nsColor: nsColor) }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// The same colour, every channel scaled. Clamped, so a factor above 1 on
    /// an already-bright swatch cannot wrap round to something else.
    public func scaled(by factor: Double) -> ThemeColor {
        func channel(_ value: Double) -> Int {
            Int((min(max(value * factor, 0), 1) * 255).rounded())
        }
        return ThemeColor(
            hex: String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
        )
    }

    /// Part of the way from this colour to another.
    ///
    /// Straight linear interpolation per channel, which is what a gradient
    /// does between two stops — so a colour taken from here lands exactly
    /// where the gradient would have drawn it. That is the whole point of it:
    /// it exists so a stack of three cards can cut one fall into three pieces
    /// without any piece starting somewhere the light was not.
    public func mixed(with other: ThemeColor, by amount: Double) -> ThemeColor {
        let t = min(max(amount, 0), 1)
        func channel(_ from: Double, _ to: Double) -> Int {
            Int(((from + (to - from) * t) * 255).rounded())
        }
        return ThemeColor(
            hex: String(
                format: "#%02X%02X%02X",
                channel(red, other.red),
                channel(green, other.green),
                channel(blue, other.blue)
            )
        )
    }

    /// The same colour with its hue turned down to at most `ceiling`, or
    /// unchanged if it was already quieter than that.
    ///
    /// Pulled towards the grey of the same *luminance* rather than towards the
    /// midpoint of its channels, so the result reads as light as the colour it
    /// came from. A green sits far above its own midpoint — take the hue out
    /// of `#8CF5A3` by averaging and the text arrives visibly darker than it
    /// was authored to be.
    public func chromaCapped(at ceiling: Double) -> ThemeColor {
        let chroma = max(red, green, blue) - min(red, green, blue)
        guard chroma > ceiling, chroma > 0 else { return self }

        let grey = luminanceLevel
        let keep = ceiling / chroma
        func channel(_ value: Double) -> Int {
            Int((min(max(grey + (value - grey) * keep, 0), 1) * 255).rounded())
        }
        return ThemeColor(hex: String(
            format: "#%02X%02X%02X", channel(red), channel(green), channel(blue)
        ))
    }

    /// Lightness as the eye takes it, before the WCAG gamma curve — which is
    /// the right measure for "a grey as light as this colour", where
    /// `luminance` is the right one for contrast.
    var luminanceLevel: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// WCAG relative luminance. Used by the contrast floor, which is the one
    /// thing standing between a pretty theme and unreadable error text.
    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, 1...21.
    public func contrast(against other: ThemeColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Everything the look of the app is made of.
///
/// Colours used to be literals at the point of use, spread across eight files,
/// which is fine for one look and impossible for six. A theme is a file now —
/// bundled ones ship with the app, and anyone can drop their own beside them
/// without building anything.
public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Drives `NSAppearance` so system controls — the switch, menus, the
    /// window's own chrome — sit on the right side of the light/dark line.
    public let isDark: Bool

    public let terminal: Terminal
    public let chrome: Chrome
    public let status: Status
    public let board: Board
    /// The theme's own small thing, drifting on the landing screen. Optional:
    /// Mono and High Contrast have none on purpose. See `Trinket`.
    public let trinket: Trinket?
    /// A line the theme gets to say for itself, in the board's alphabet.
    ///
    /// It is not on the screen. Press the wordmark and the tagline gives way to
    /// it for a moment, along with a flurry of whatever the trinket is — which
    /// is the whole of it, and the reason it is allowed to exist. A landing
    /// page was just cut from seven things to five for being a menu with no
    /// order to it, and the way to put personality back into a page like that
    /// is not to add a sixth line everyone has to read forever.
    ///
    /// Uppercase, and out of `DotMatrix`'s 5x7 alphabet — A to Z, the digits,
    /// and a handful of marks. A character outside it draws as a blank cell
    /// rather than failing anywhere anyone would notice, which is what the
    /// tests are for.
    public let flavour: String?

    /// What this theme calls the three things the app has to say out loud.
    ///
    /// Colour is the only thing a theme changed until now, which is why
    /// fourteen of them read as one app with the hue turned: the words were
    /// the same words in every one. A theme with a voice says the same fact
    /// in its own register — Matrix reports a build the way Matrix would.
    ///
    /// Only the wording moves. What the sentence *means* is fixed by the
    /// state it came from, so a theme cannot make a failure sound like a
    /// success however it phrases it, and every line has a default underneath
    /// it for the themes and the user files that say nothing.
    public let voice: Voice?

    /// The theme's feel, as distinct from its colour: the shape of the caret,
    /// how hard the light lands on the panels, how far the board's lamps
    /// bloom, and how heavily the chrome is set.
    ///
    /// These were constants at the point of use — one sheen opacity, one blur
    /// — so every theme was the same object painted over. Steel is lit flat;
    /// Sakura blooms. The numbers a theme leaves out fall back to what those
    /// constants were, so a theme that says nothing here looks exactly as it
    /// did.
    ///
    /// The corner radius and the chrome typeface used to sit here too. They
    /// went further than a theme should: a different cut and a different face
    /// stop reading as one app in another colour and start reading as another
    /// app. Both are house constants now.
    public let texture: Texture?

    /// The faint motif behind the panels — petals for Sakura, rain for Matrix,
    /// brushed grain for Steel.
    ///
    /// `texture` above is how hard the light lands; this is what the surface
    /// is made of. Two names for two different things, and the second one is
    /// the one you can point at.
    ///
    /// Optional, and High Contrast has none on purpose: texture is the last
    /// thing that helps somebody who needed to turn contrast up. Everything
    /// else carries one, because a theme without a surface of its own is a
    /// palette rather than a theme.
    public let pattern: Motif?

    /// The words. Every field optional, and every one with a default in
    /// `resolvedVoice` — a theme opts into as much of its own register as it
    /// has something to say in.
    public struct Voice: Codable, Sendable, Equatable {
        /// An agent is working. "Currently something is building."
        public let working: String?
        /// It stopped, and cleanly.
        public let done: String?
        /// What this theme calls a tab that has rung for you. Optional like
        /// every other line here, so a theme file written before the state
        /// existed still loads.
        public let needsYou: String?
        /// It stopped, and did not. The exit code is appended by the caller,
        /// so this line does not carry a number.
        public let stopped: String?
        /// Nothing is running and nothing is open. "All the items are closed."
        public let clear: String?
        /// One line about the theme itself, under its name in the picker.
        public let blurb: String?
    }

    /// The feel. Same rule: absent means the house number.
    public struct Texture: Codable, Sendable, Equatable {
        /// `block`, `underline` or `bar`, each blinking. Anything else — a
        /// typo in somebody's file — reads as the house bar rather than
        /// failing, which is the rule every other field in a theme follows.
        public let caret: String?
        /// How much of the sheen lands on the top card, as a multiple of the
        /// house 0.035. 0 puts a theme's panels in flat light.
        public let sheen: Double?
        /// How far a lit lamp blooms, as a multiple of the diffuser the
        /// surface already had — the board and the meter were drawn at
        /// slightly different radii and both are worth keeping. 1 is as
        /// drawn; 0 is an LED with no glass over it at all.
        public let bloom: Double?
        /// `light`, `regular` or `heavy`: which way the chrome's weights are
        /// shifted from what each call site asks for.
        public let weight: String?
    }

    /// The terminal surface. SwiftTerm owns the drawing; these are the knobs
    /// it exposes.
    public struct Terminal: Codable, Sendable, Equatable {
        public let background: ThemeColor
        public let foreground: ThemeColor
        public let cursor: ThemeColor
        public let selection: ThemeColor
        /// Exactly sixteen: the eight ANSI colours and their bright variants,
        /// in the order the terminal indexes them.
        public let ansi: [ThemeColor]
        public let fontName: String
        public let fontSize: Double
    }

    /// The app around the terminal.
    public struct Chrome: Codable, Sendable, Equatable {
        public let panelTop: ThemeColor
        public let panelBottom: ThemeColor
        /// Behind the terminal text, over the window's glass.
        public let bed: ThemeColor
        public let bedOpacity: Double
        public let rowHover: ThemeColor
        public let rowSelected: ThemeColor
        public let border: ThemeColor
        public let textPrimary: ThemeColor
        public let textSecondary: ThemeColor
        public let textTertiary: ThemeColor
        public let accent: ThemeColor
    }

    /// What a tab is doing. Semantic, so it stays legible rather than pretty:
    /// a theme may recolour these but they still have to mean stop and go.
    public struct Status: Codable, Sendable, Equatable {
        public let idle: ThemeColor
        public let running: ThemeColor
        public let succeeded: ThemeColor
        public let failed: ThemeColor
    }

    /// The departure board on the empty screen.
    public struct Board: Codable, Sendable, Equatable {
        public let lit: ThemeColor
        public let litDim: ThemeColor
        public let unlit: ThemeColor
        public let backdrop: ThemeColor
        public let highlight: ThemeColor
    }
}

// MARK: - Fonts

public extension Theme.Terminal {
    /// The font, or the system monospace at the same size if the named one is
    /// missing or proportional.
    ///
    /// A terminal lays out on a character cell, so a proportional face does not
    /// look wrong, it tears: every column after the first drifts. Falling back
    /// is better than rendering garbage, and `ThemeReport` names the theme that
    /// caused it.
    var resolvedFont: NSFont {
        if let font = NSFont(name: fontName, size: fontSize), font.isFixedPitch {
            return font
        }
        if let geist = NSFont(name: BundledFonts.mono, size: fontSize) { return geist }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var fontIsUsable: Bool {
        NSFont(name: fontName, size: fontSize)?.isFixedPitch ?? false
    }

    /// How much hue the text you read all day is allowed to carry.
    ///
    /// Body text is white with a *tinge* of the theme, not the theme's colour
    /// set as words. Thirteen of the fourteen bundled themes were already
    /// written that way, at a chroma between 0.01 and 0.13 — Matrix was the
    /// exception at 0.41, and its screen was the one where the text was the
    /// theme rather than wearing it.
    ///
    /// A ceiling rather than a fixed amount, because the themes that were
    /// already right must come through untouched: this takes the loud ones
    /// down to the level the quiet ones already sit at, and leaves everything
    /// below it alone. It applies to anyone's own theme too, which a
    /// hand-edited palette would not have.
    ///
    /// Set a hair above Ember's 0.133 rather than through it. A ceiling that
    /// cuts the loudest theme that was already right is a ceiling in the wrong
    /// place — it would be trimming a colour somebody had chosen, by an amount
    /// too small to see.
    static var textChroma: Double { 0.14 }

    /// The colour body text is actually drawn in.
    var text: ThemeColor { foreground.chromaCapped(at: Self.textChroma) }

    /// The sixteen as they are drawn.
    ///
    /// The two whites answer to the same ceiling as the text: they *are* the
    /// text colour in every bundled theme, so capping one and not the other
    /// would leave a program printing in white looking greener than the line
    /// above it.
    var palette: [ThemeColor] {
        ansi.enumerated().map { index, colour in
            index == 7 || index == 15 ? colour.chromaCapped(at: Self.textChroma) : colour
        }
    }
}

public extension Theme {
    /// A chrome font, in the one face the app is set in.
    ///
    /// A theme used to be able to name its own typeface. It made every theme
    /// a different-looking app rather than the same app in another colour,
    /// which is further than a theme is meant to go — so the face is Geist
    /// everywhere now, and only a broken bundle falls past it to the system.
    ///
    /// `Font.custom` carries no weight of its own, so the weight is applied
    /// after and SwiftUI synthesises it where the family has no such cut.
    func uiFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let shifted = shape.shift(weight)
        guard NSFont(name: BundledFonts.ui, size: size) != nil else {
            return .system(size: size, weight: shifted)
        }
        return .custom(BundledFonts.ui, fixedSize: size).weight(shifted)
    }

    /// The theme's words, with the house line standing in wherever it has
    /// none. Nothing downstream reads `voice` directly — a caller that did
    /// would have to carry its own default, which is how fourteen themes came
    /// to share one vocabulary in the first place.
    var speech: Speech {
        Speech(
            working: voice?.working ?? "Something is building",
            done: voice?.done ?? "A build has completed",
            // Every theme file predates this field, so every theme gets the
            // house line until it says otherwise — the same rule the rest of
            // `speech` follows, and the reason a user's own theme file does
            // not come up with an empty menu bar.
            needsYou: voice?.needsYou ?? "Something is asking for you",
            stopped: voice?.stopped ?? "A build stopped short",
            clear: voice?.clear ?? "All the items are closed",
            blurb: voice?.blurb
        )
    }

    /// The theme's feel, with the house numbers standing in. Same rule as
    /// `speech`, for the same reason.
    var shape: Shape {
        Shape(
            caret: Shape.Caret(named: texture?.caret),
            sheen: (texture?.sheen ?? 1) * Shape.houseSheen,
            bloom: texture?.bloom ?? Shape.houseBloom,
            weight: Shape.Weight(named: texture?.weight)
        )
    }

    /// A theme's voice with every line filled in. Resolved once, at the top of
    /// `speech`, so no view has to know which lines a theme bothered to write.
    struct Speech: Sendable, Equatable {
        public let working: String
        public let done: String
        /// What this theme calls a tab that has rung for you.
        public let needsYou: String
        public let stopped: String
        public let clear: String
        public let blurb: String?
    }

    /// A theme's feel with every number filled in.
    struct Shape: Sendable, Equatable {
        /// The cut every panel in the app is drawn at. It was briefly a
        /// per-theme number; fourteen different radii read as fourteen
        /// different apps, so it is one constant again.
        public static let houseCorner: Double = 12
        /// The house sheen: the opacity the top card's highlight was drawn at.
        public static let houseSheen: Double = 0.035
        /// The diffuser as each surface already drew it.
        public static let houseBloom: Double = 1

        public let caret: Caret
        public let sheen: Double
        public let bloom: Double
        public let weight: Weight

        /// The shape of the thing you type in front of.
        public enum Caret: String, Sendable {
            case bar, block, underline

            /// A name out of a theme file. Unknown — a typo, or a field from a
            /// newer Ocarina — is the house bar, which is the rule the rest of
            /// the theme layer follows: a bad value costs you that one thing,
            /// never the app.
            init(named: String?) {
                self = Caret(rawValue: (named ?? "").lowercased()) ?? .bar
            }
        }

        /// Which way the chrome's weights are pushed from what a view asks
        /// for. A whole theme set one step down reads as a lighter object,
        /// which is most of what separates a serif theme from a steel one.
        public enum Weight: String, Sendable {
            case light, regular, heavy

            init(named: String?) {
                self = Weight(rawValue: (named ?? "").lowercased()) ?? .regular
            }
        }

        /// The weight a view asked for, moved by the theme's own step.
        ///
        /// Along the ordered scale rather than by arithmetic on a raw value:
        /// `Font.Weight` has no addition, and the ends have to clamp — a theme
        /// asking for lighter than `.ultraLight` gets `.ultraLight`, not a
        /// wrapped-round black.
        func shift(_ weight: Font.Weight) -> Font.Weight {
            guard self.weight != .regular else { return weight }
            let scale: [Font.Weight] = [
                .ultraLight, .thin, .light, .regular,
                .medium, .semibold, .bold, .heavy, .black,
            ]
            guard let index = scale.firstIndex(of: weight) else { return weight }
            let step = self.weight == .light ? -1 : 1
            return scale[min(max(index + step, 0), scale.count - 1)]
        }
    }
}

// MARK: - Legibility

/// What is wrong with a theme, if anything.
///
/// This exists because the people this app is for cannot yet read an error
/// message, so text they cannot see is not a cosmetic problem — it ends the
/// session. Every bundled theme is checked against this in the test suite, and
/// a user's own theme is checked when it loads.
public struct ThemeReport: Sendable, Equatable {
    /// WCAG AA for normal text. Terminal output is small and dense, so this is
    /// a floor and not a target.
    public static let minimumContrast: Double = 4.5

    public struct Finding: Sendable, Equatable {
        public let what: String
        public let ratio: Double
    }

    public let themeID: String
    public let unreadable: [Finding]
    public let fontFellBack: Bool

    public var isUsable: Bool { unreadable.isEmpty }

    public init(theme: Theme) {
        themeID = theme.id
        fontFellBack = !theme.terminal.fontIsUsable

        let background = theme.terminal.background
        var findings: [Finding] = []

        func check(_ name: String, _ colour: ThemeColor, floor: Double = ThemeReport.minimumContrast) {
            let ratio = colour.contrast(against: background)
            if ratio < floor { findings.append(Finding(what: name, ratio: ratio)) }
        }

        // What is drawn, not what was written down: the text and the two
        // whites are capped on their way to the screen, so the floor has to be
        // measured against the colours that actually arrive there.
        check("foreground", theme.terminal.text)

        // The two extremes of the ramp — ANSI 0 and 15 — are the pair a theme
        // uses as a *ground*: black is the background on a dark theme, white on
        // a light one. Holding them to the reading floor would force ANSI black
        // to be mid-grey, which is no longer black and breaks every program
        // that picks it deliberately. They still have to be visible when a
        // program does print in them, so they answer to the 3:1 bar.
        //
        // Everything between them is text somebody reads, including ANSI 8,
        // which is where dim output and comments land.
        for (index, colour) in theme.terminal.palette.enumerated() {
            let isGround = index == 0 || index == 15
            check("ansi[\(index)]", colour, floor: isGround ? 3 : ThemeReport.minimumContrast)
        }
        // The cursor is a block the width of a cell; it only has to be seen,
        // not read through, so it answers to a lower bar.
        check("cursor", theme.terminal.cursor, floor: 3)

        unreadable = findings
    }
}

// MARK: - SwiftTerm bridging

public extension ThemeColor {
    /// SwiftTerm keeps sixteen bits per channel; `red8:` scales an 8-bit value.
    var swiftTermColor: SwiftTerm.Color {
        SwiftTerm.Color(
            red8: UInt16(red * 255),
            green8: UInt16(green * 255),
            blue8: UInt16(blue * 255)
        )
    }
}

public extension Theme.Shape.Caret {
    /// SwiftTerm's own name for the same shape. Blinking in all three cases:
    /// the caret is the one thing on the screen that has to be findable
    /// without looking for it, and a steady one in a wall of output is not.
    ///
    /// A program can still ask for another shape through the usual escape
    /// sequence; the theme only decides what a fresh shell starts with.
    var swiftTermStyle: SwiftTerm.CursorStyle {
        switch self {
        case .bar: .blinkBar
        case .block: .blinkBlock
        case .underline: .blinkUnderline
        }
    }
}

public extension Theme {
    /// The window's own ground: what shows in the gaps between the panels, and
    /// behind the titlebar.
    ///
    /// Derived rather than declared. A new field in `Chrome` would mean
    /// editing every bundled theme, and would come back mid-grey on anybody's
    /// own theme file — a window whose ground is grey while its panels are the
    /// palette is exactly the mismatch this exists to fix.
    ///
    /// It is the sidebar's darker end taken one step further from the text, so
    /// the cards sit *in front of* it rather than level with it. A dark theme
    /// can take a real step down; a light one cannot, or the frame around the
    /// panels reads as a shadow rather than as a surface.
    var ground: ThemeColor {
        chrome.panelBottom.scaled(by: isDark ? 0.62 : 0.94)
    }
}
