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
    public let typography: Typography?
    /// The faint motif behind the panels. Optional: High Contrast has none on
    /// purpose, because texture is the last thing that helps somebody who
    /// needed to turn contrast up.
    public let pattern: Motif?

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

    /// The face the app's own chrome is set in.
    ///
    /// Colour and texture only get a theme so far. A terminal in Futura and a
    /// terminal in Georgia are different objects before you have read a word of
    /// either, and typeface is the cheapest personality there is — it ships
    /// with the system and costs nothing to draw.
    public struct Typography: Codable, Sendable, Equatable {
        /// Nil means the system face, which is the right answer for the
        /// neutral themes and for High Contrast.
        public let uiFontName: String?
        /// Some faces run small or large at the same point size.
        public let uiSizeAdjust: Double?
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
}

public extension Theme {
    /// A chrome font in this theme's face, falling back to the system.
    ///
    /// `Font.custom` carries no weight of its own, so the weight is applied
    /// after and SwiftUI synthesises it where the family has no such cut.
    func uiFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // A theme may still name its own face — a user theme in
        // `~/.ocarina/themes` can — but the bundled ones all use Geist, and
        // Geist is what anything unspecified gets.
        let name = typography?.uiFontName ?? BundledFonts.sans
        guard NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        let adjusted = size + (typography?.uiSizeAdjust ?? 0)
        return .custom(name, fixedSize: adjusted).weight(weight)
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

        check("foreground", theme.terminal.foreground)

        // The two extremes of the ramp — ANSI 0 and 15 — are the pair a theme
        // uses as a *ground*: black is the background on a dark theme, white on
        // a light one. Holding them to the reading floor would force ANSI black
        // to be mid-grey, which is no longer black and breaks every program
        // that picks it deliberately. They still have to be visible when a
        // program does print in them, so they answer to the 3:1 bar.
        //
        // Everything between them is text somebody reads, including ANSI 8,
        // which is where dim output and comments land.
        for (index, colour) in theme.terminal.ansi.enumerated() {
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
