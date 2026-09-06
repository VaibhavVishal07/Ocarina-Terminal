import Foundation

/// Puts the theme back in charge of colours a program picked for itself.
///
/// A theme sets the sixteen ANSI colours, and for a long time that was the
/// whole of a terminal's palette — a program asked for red and the theme said
/// which red. It is no longer how the tools people run actually colour
/// themselves. Claude Code, and every other TUI built on the same libraries,
/// sends 24-bit colour: not "red" but `38;2;217;119;87`, the exact orange of
/// its own brand. Nothing a theme can set touches that, so choosing a green
/// theme and opening an agent gave you a green window with an orange program
/// sitting in it.
///
/// This rewrites those requests on the way in — but only some of them, and the
/// restraint is the whole design. See `rendering(for:isForeground:)`: red and
/// green are left exactly as the program sent them, a program's own accent is
/// toned down to the text colour, and only the cool decorative hues take the
/// theme's own. Sending every hue to its nearest slot was the first attempt and
/// it lost the one thing colour in a terminal is actually load-bearing for —
/// against a theme built around a single hue, added lines and removed lines
/// came back the same colour.
///
/// The eight ANSI colours and their bright variants pass through untouched:
/// those were already the theme's to answer, and a program that asks for "red"
/// is asking the question this is trying to restore.
///
/// The ground is a case of its own. A program that paints its background the
/// same colour as the terminal's is not asking for a colour, it is asking for
/// the background — so that becomes the *default* background rather than the
/// theme's black, and the window's glass shows through it as it should. The
/// same holds for a foreground that is already the theme's text colour.
public struct PaletteFilter: Sendable {
    /// Whether this rewrites anything at all. Off, `filter` is the identity.
    public var isEnabled: Bool
    /// The two colours a program can name that mean "the default".
    private var background: ThemeColor
    private var foreground: ThemeColor
    /// The theme's sixteen, so a mapping can be checked before it is made.
    /// See `wouldReadAsSemantic`.
    private var ansi: [ThemeColor]

    /// A partial escape sequence at the end of the last read.
    ///
    /// A pty read stops wherever the buffer filled, which is regularly halfway
    /// through `38;2;217;119;87m`. The tail is held here and put back in front
    /// of the next read, because rewriting half a sequence is worse than not
    /// rewriting it.
    private var carry: [UInt8] = []

    /// How long a held fragment may get before it is let through as it is.
    ///
    /// A sequence this long is not a sequence; it is a stream of bytes that
    /// happened to start with `ESC [`, and holding it would swallow output.
    private static let carryLimit = 128

    public init(theme: Theme, isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        background = theme.terminal.background
        foreground = theme.terminal.foreground
        ansi = theme.terminal.ansi
    }

    public mutating func use(_ theme: Theme) {
        background = theme.terminal.background
        foreground = theme.terminal.foreground
        ansi = theme.terminal.ansi
    }

    // MARK: - The stream

    /// One read from the pty, with its colour requests rewritten.
    public mutating func filter(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard isEnabled else {
            guard carry.isEmpty else {
                let held = carry
                carry = []
                return held + bytes
            }
            return Array(bytes)
        }

        let input = carry.isEmpty ? Array(bytes) : carry + bytes
        carry = []

        var output: [UInt8] = []
        output.reserveCapacity(input.count)
        var index = 0

        while index < input.count {
            guard input[index] == 0x1B, index + 1 < input.count else {
                if input[index] == 0x1B {
                    // A lone escape at the very end: the rest is coming.
                    carry = [0x1B]
                    break
                }
                output.append(input[index])
                index += 1
                continue
            }
            guard input[index + 1] == 0x5B else {   // `[`
                output.append(input[index])
                index += 1
                continue
            }

            // Parameter and intermediate bytes, then the one that ends it.
            var end = index + 2
            while end < input.count, input[end] >= 0x20, input[end] <= 0x3F { end += 1 }
            guard end < input.count else {
                let fragment = input[index...]
                if fragment.count > Self.carryLimit {
                    output.append(contentsOf: fragment)
                } else {
                    carry = Array(fragment)
                }
                break
            }

            if input[end] == 0x6D,   // `m`
               let rewritten = rewritten(String(decoding: input[(index + 2)..<end], as: UTF8.self)) {
                output.append(contentsOf: Array("\u{1B}[\(rewritten)m".utf8))
            } else {
                output.append(contentsOf: input[index...end])
            }
            index = end + 1
        }
        return output
    }

    // MARK: - One SGR sequence

    /// The parameters of an `m` sequence, rewritten — or nil when there was
    /// nothing in it to rewrite, which is almost every one of them.
    func rewritten(_ parameters: String) -> String? {
        var parts = parameters
            .split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init)
        var changed = false
        var index = 0

        while index < parts.count {
            let part = parts[index]
            // `38:2::r:g:b` — the same colour written with sub-parameters,
            // which is one parameter rather than five.
            if part.contains(":") {
                if let replacement = rewrittenSubparameters(part) {
                    parts[index] = replacement
                    changed = true
                }
                index += 1
                continue
            }

            guard part == "38" || part == "48", index + 1 < parts.count else {
                index += 1
                continue
            }
            let isForeground = part == "38"

            if parts[index + 1] == "5", index + 2 < parts.count,
               let slot = Int(parts[index + 2]) {
                // 0–15 are the theme's already; the rest are a fixed cube.
                guard slot >= 16, let colour = Self.cube(slot),
                      let mapped = replacement(for: colour, isForeground: isForeground)
                else { index += 3; continue }
                parts.replaceSubrange(index...(index + 2), with: mapped)
                changed = true
                index += mapped.count
                continue
            }

            if parts[index + 1] == "2", index + 4 < parts.count,
               let red = Int(parts[index + 2]),
               let green = Int(parts[index + 3]),
               let blue = Int(parts[index + 4]) {
                guard let mapped = replacement(
                    for: ThemeColor(red: red, green: green, blue: blue),
                    isForeground: isForeground
                ) else { index += 5; continue }
                parts.replaceSubrange(index...(index + 4), with: mapped)
                changed = true
                index += mapped.count
                continue
            }

            index += 1
        }

        return changed ? parts.joined(separator: ";") : nil
    }

    private func rewrittenSubparameters(_ part: String) -> String? {
        let fields = part.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let lead = fields.first, lead == "38" || lead == "48", fields.count >= 3 else {
            return nil
        }
        let isForeground = lead == "38"

        if fields[1] == "5", let slot = Int(fields[2]) {
            guard slot >= 16, let colour = Self.cube(slot) else { return nil }
            return replacement(for: colour, isForeground: isForeground)?.joined(separator: ":")
        }
        // With sub-parameters the colour space id is present but usually
        // empty, so the channels are the last three fields either way.
        if fields[1] == "2", fields.count >= 5,
           let red = Int(fields[fields.count - 3]),
           let green = Int(fields[fields.count - 2]),
           let blue = Int(fields[fields.count - 1]) {
            return replacement(
                for: ThemeColor(red: red, green: green, blue: blue),
                isForeground: isForeground
            )?.joined(separator: ":")
        }
        return nil
    }

    /// What one named colour becomes, or nil to leave it exactly as it came.
    private func replacement(for colour: ThemeColor, isForeground: Bool) -> [String]? {
        let ground = isForeground ? foreground : background
        // Already the colour it would have got by saying nothing.
        if colour.isNear(ground) { return [isForeground ? "39" : "49"] }

        switch Self.rendering(for: colour, isForeground: isForeground) {
        case .unchanged:
            return nil
        case .neutral:
            // Named in full rather than sent to a palette slot, because every
            // slot in the palette is the theme's — including the two whites.
            let plain = foreground.desaturated
            return [
                isForeground ? "38" : "48", "2",
                String(plain.byte(\.red)), String(plain.byte(\.green)), String(plain.byte(\.blue))
            ]
        case .slot(let slot):
            // The theme's answer, checked before it is given. A palette built
            // around one hue answers "blue" with a green, and the colour Claude
            // Code paints the *selected* option of a yes/no prompt in is that
            // blue — so on Matrix, "No, exit" came up green. A recolour is
            // allowed to change how decoration looks; it is not allowed to
            // turn it into something that reads as go or stop.
            guard slot < ansi.count, !Self.wouldReadAsSemantic(ansi[slot]) else { return nil }
            return [isForeground ? "38" : "48", "5", String(slot)]
        }
    }

    /// Whether a colour would be read as pass or fail rather than as
    /// decoration. The test is on the theme's swatch, not on the program's.
    static func wouldReadAsSemantic(_ colour: ThemeColor) -> Bool {
        let family = Self.family(of: colour)
        return family == .red || family == .green
    }

    // MARK: - What a colour is allowed to become

    /// The three answers a colour can get.
    enum Rendering: Equatable {
        /// The program keeps its colour. What red and green mean is not the
        /// theme's business, and neither is a grey.
        case unchanged
        /// Plain text: the theme's foreground with the hue taken out of it.
        case neutral
        /// One of the sixteen, which the theme then answers for.
        case slot(Int)
    }

    /// What to do with a colour a program named in full.
    ///
    /// The first version of this sent every hue to its nearest ANSI slot, and
    /// it was too much. Two colours a program was using to mean opposite
    /// things came out the same: in a theme built around one hue — Matrix,
    /// where the palette's "yellow" is a green — an agent's gold chrome and
    /// its added lines both arrived green, and *added* against *removed* is
    /// exactly the distinction you cannot afford to lose in a diff.
    ///
    /// So the rule is now narrow, and it is about what a colour is *for*:
    ///
    /// - **Red and green are left alone.** They are the only two colours in a
    ///   terminal that carry meaning rather than decoration — failed and
    ///   passed, removed and added, error and ok. A theme does not get a vote
    ///   on those.
    /// - **A program's own accent is toned down to plain text.** The gold
    ///   Claude Code paints its chrome in is branding, not information: it is
    ///   the one colour that is loud on every screen and says nothing that the
    ///   words next to it do not.
    ///
    ///   Plain text here means the theme's foreground *with the hue taken out
    ///   of it* — near-white on a dark theme, near-black on a light one — and
    ///   not the foreground itself. The foreground is not neutral in every
    ///   theme: Matrix sets it to `#8CF5A3`, so an accent handed the theme's
    ///   text colour came out bright green, which is a long way from toned
    ///   down. Anything a theme owns carries the theme's hue; the way to
    ///   *stop* a colour shouting is to give it no hue at all.
    /// - **The cool hues take the theme's own** — but only where the theme's
    ///   answer is still a cool hue. Blue, cyan and magenta are where a TUI
    ///   draws its furniture, and furniture is decoration; the guard on the
    ///   answer is in `replacement(for:isForeground:)`.
    /// - **Greys are left alone.** A grey is already neutral, so there is
    ///   nothing in it for a theme to answer — and answering anyway is how a
    ///   program's quiet secondary text came back tinted, which is the same
    ///   muddle from the other end.
    static func rendering(for colour: ThemeColor, isForeground: Bool) -> Rendering {
        let high = max(colour.red, colour.green, colour.blue)
        let low = min(colour.red, colour.green, colour.blue)
        let lightness = (high + low) / 2

        let base: Int
        switch family(of: colour) {
        // A grey is already the absence of a colour. Sent to the theme's own
        // grey ramp it stops being one — those swatches are pulled towards the
        // theme's hue like everything else in the palette, so a program's
        // secondary text arrived faintly green, or faintly pink.
        case .grey: return .unchanged
        case .red: return .unchanged            // negative
        case .green: return .unchanged          // positive
        case .warm:                             // orange and gold: the accent
            // Only as text. A warm *background* is a highlighted row or a
            // marked block, and painting that in the text colour would leave a
            // white bar where a program meant to point at something.
            return isForeground ? .neutral : .slot(11)
        case .cyan: base = 6
        case .blue: base = 4
        case .magenta: base = 5
        }
        // The bright half of the palette is for the colours a program chose to
        // be loud in — which is a question about how far the strongest channel
        // is pushed, not about lightness. A fully saturated hue sits at exactly
        // half lightness whether it is maroon or vermilion, so on lightness
        // alone every vivid colour a program owns would come back in the dim
        // half of the palette.
        return .slot(high > 0.88 || lightness > 0.65 ? base + 8 : base)
    }

    /// The six hues a colour can belong to, and grey for the ones that do not.
    ///
    /// One classifier for two jobs: deciding what a program's colour should
    /// become, and checking what the theme is about to answer with. They have
    /// to agree, or the guard would be reading the palette by a different rule
    /// from the one that chose the slot.
    enum Family: Equatable {
        case grey, red, warm, green, cyan, blue, magenta
    }

    static func family(of colour: ThemeColor) -> Family {
        let high = max(colour.red, colour.green, colour.blue)
        let low = min(colour.red, colour.green, colour.blue)
        let chroma = high - low
        guard chroma > 0.09 else { return .grey }

        var hue: Double
        switch high {
        case colour.red: hue = (colour.green - colour.blue) / chroma
        case colour.green: hue = 2 + (colour.blue - colour.red) / chroma
        default: hue = 4 + (colour.red - colour.green) / chroma
        }
        hue *= 60
        if hue < 0 { hue += 360 }

        switch hue {
        case ..<12, 345...: return .red
        case ..<70: return .warm
        case ..<160: return .green
        case ..<200: return .cyan
        case ..<260: return .blue
        default: return .magenta
        }
    }

    /// The 256-colour cube, as colours. Indices below 16 are the ANSI palette
    /// and are not this function's business.
    static func cube(_ index: Int) -> ThemeColor? {
        switch index {
        case 16...231:
            let offset = index - 16
            let steps = [0, 95, 135, 175, 215, 255]
            return ThemeColor(
                red: steps[(offset / 36) % 6],
                green: steps[(offset / 6) % 6],
                blue: steps[offset % 6]
            )
        case 232...255:
            let level = 8 + (index - 232) * 10
            return ThemeColor(red: level, green: level, blue: level)
        default:
            return nil
        }
    }
}

extension ThemeColor {
    init(red: Int, green: Int, blue: Int) {
        self.init(hex: String(
            format: "#%02X%02X%02X",
            min(max(red, 0), 255),
            min(max(green, 0), 255),
            min(max(blue, 0), 255)
        ))
    }

    /// The same colour with the hue taken out: a grey as light as this one is.
    ///
    /// Weighted by how much of the light the eye takes from each channel, so a
    /// theme's foreground keeps the weight it was chosen for. Averaging the
    /// channels instead would send a green text colour to a grey a good deal
    /// darker than it reads.
    var desaturated: ThemeColor {
        let level = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let byte = Int((min(max(level, 0), 1) * 255).rounded())
        return ThemeColor(red: byte, green: byte, blue: byte)
    }

    /// One channel as the 0–255 a terminal writes.
    func byte(_ channel: KeyPath<ThemeColor, Double>) -> Int {
        Int((min(max(self[keyPath: channel], 0), 1) * 255).rounded())
    }

    /// Near enough to be the same colour to a reader. Straight RGB distance:
    /// this is a "did the program just name the background" test, not a
    /// perceptual match.
    func isNear(_ other: ThemeColor, tolerance: Double = 0.12) -> Bool {
        let dr = red - other.red, dg = green - other.green, db = blue - other.blue
        return (dr * dr + dg * dg + db * db).squareRoot() <= tolerance
    }
}
