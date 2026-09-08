import SwiftUI

/// A 5x7 dot-matrix panel, drawn the way a departure board is built: every cell
/// in the grid is painted, dark when it is off, so the matrix stays visible
/// behind the words instead of the text floating on black.
struct DotMatrixText: View {
    /// How far a lit cell blooms is the theme's — a board can be a hard-edged
    /// panel of lamps or a haze of them. Read from the environment rather
    /// than passed: every place this is drawn is already inside the themed
    /// tree, and four call sites forwarding the same value is four places to
    /// forget it.
    @Environment(\.theme) private var theme
    let text: String
    var cell: CGFloat = 3.4
    var gap: CGFloat = 1.2
    var lit: Color
    var unlit: Color
    /// Lit cells bloom, the way an LED board does behind its diffuser.
    var glow: Bool = true

    /// The dots lighting one at a time, in the order the glyphs are built.
    ///
    /// The chase the marks on the website run, at the website's speed, and it
    /// says the same thing here that it says there: a board tells you it is
    /// live by its own lamps moving. In the app it is on while an agent is
    /// working in any tab, so the mark answers "is anything still going" from
    /// across the room, without a second spinner in the window.
    ///
    /// Off by default, and deliberately: every other place this is drawn is a
    /// label — a token figure, an empty state, a heading — and a label that
    /// shimmers is a label you cannot stop reading. The head takes the
    /// board's `highlight`, so it is the mark's own brightest lamp rather
    /// than a white this theme never uses.
    var chase: Bool = false

    /// How much of the word has lit, left to right, 0 to 1.
    ///
    /// A board powers on. A mark that is simply *there* the instant a screen
    /// appears is a picture of a board, and the landing screen is the one
    /// place with the room and the reason to show the difference — nothing
    /// else is on it yet, so the app lighting up its own name is the arrival
    /// rather than an interruption of one.
    ///
    /// By column, which is the order the chase travels in too, so the arrival
    /// and the motion that follows it are one gesture at two speeds. A column
    /// not yet reached is drawn in the unlit colour rather than left out: the
    /// dark half of the board is what makes it a board.
    var reveal: Double = 1

    /// One dot every 72ms, a trail of fifteen behind the head, and 26 dots of
    /// dark between passes. The website's numbers, so the mark in the app and
    /// the mark on the page move at one speed rather than at two that are
    /// nearly the same.
    private static let dwell: Double = 0.072
    private static let trail: Double = 15
    private static let rest: Double = 26
    /// How far in front of itself the head starts bringing a lamp up. Without
    /// it a dot snaps to full and the chase reads as a row of blinks.
    private static let lead: Double = 1.4
    /// The lamp under the head swells as it brightens, by the same fraction
    /// the website grows its dots. Colour alone reads as a flicker; colour
    /// and size together read as a lamp being driven harder.
    private static let swell: Double = 0.21
    /// 30fps rather than the display's own rate. The trail takes a second to
    /// cross a dot, so nothing about this is quick enough to need 120 — and
    /// the mark is 287 cells repainted every frame for as long as an agent is
    /// working, which is exactly the kind of thing that should not cost a
    /// display refresh.
    private static let frameInterval: Double = 1.0 / 30

    private var pitch: CGFloat { cell + gap }
    private var columns: Int { max(0, text.count * 6 - 1) }

    var body: some View {
        // Paused when nothing is chasing, so a still mark costs no frames at
        // all — which is every mark in the app but this one.
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !chase)) { timeline in
            Canvas { context, _ in
                paint(context, at: timeline.date)
            }
        }
        .frame(
            width: CGFloat(columns) * pitch - gap,
            height: CGFloat(Self.height) * pitch - gap
        )
        .accessibilityLabel(text)
    }

    private func paint(_ context: GraphicsContext, at now: Date) {
        let bits = Self.bitmap(for: text)

        // Where the head is, and which lit cell each rank belongs to.
        //
        // Column by column, top to bottom — through the O, then the C, and on
        // across the word. That is the order the glyphs are built in and the
        // order the head has to travel in: row by row instead would sweep the
        // mark in seven horizontal bands, which is a scan and not a chase.
        var rank = [Int: Double]()
        var litCells = 0
        for column in 0..<columns {
            for row in 0..<Self.height where bits[row][column] {
                rank[row * columns + column] = Double(litCells)
                litCells += 1
            }
        }
        let total = Double(litCells) + Self.rest
        let head: Double = chase && litCells > 0
            ? (now.timeIntervalSinceReferenceDate / Self.dwell)
                .truncatingRemainder(dividingBy: total)
            : -1

        /// How hard this lamp is being driven, 0 for every dot outside the
        /// trail.
        func drive(_ position: Double) -> Double {
            guard head >= 0 else { return 0 }
            var distance = head - position
            // The head wraps. A dot near the end of the word is still fading
            // out while the head is back at the start of the next pass, so
            // the distance has to be measured round the loop rather than
            // straight down it.
            if distance < -Self.lead { distance += total }
            if distance >= 0, distance < Self.trail { return 1 - distance / Self.trail }
            if distance < 0, distance > -Self.lead { return 1 + distance / Self.lead }
            return 0
        }

        var all = Path(), off = Path(), still = Path()
        var driven: [(Path, Double)] = []

        // How far along the word the light has got. Clamped rather than
        // trusted: this is animated from outside, and SwiftUI will overshoot a
        // spring straight past 1.
        let arrived = min(max(reveal, 0), 1) * Double(columns)

        for row in 0..<Self.height {
            for column in 0..<columns {
                let box = CGRect(
                    x: CGFloat(column) * pitch,
                    y: CGFloat(row) * pitch,
                    width: cell,
                    height: cell
                )
                guard bits[row][column], Double(column) < arrived else {
                    off.addPath(Path(roundedRect: box, cornerRadius: cell * 0.3))
                    continue
                }
                let dot = Path(roundedRect: box, cornerRadius: cell * 0.3)
                // The bloom is taken over every lit cell, driven or not, so
                // turning the chase on does not change the haze the board
                // sits in.
                all.addPath(dot)

                let k = drive(rank[row * columns + column] ?? 0)
                guard k > 0 else { still.addPath(dot); continue }
                let grow = cell * Self.swell * k
                let swollen = box.insetBy(dx: -grow / 2, dy: -grow / 2)
                driven.append((
                    Path(roundedRect: swollen, cornerRadius: (cell + grow) * 0.3), k
                ))
            }
        }

        context.fill(off, with: .color(unlit))
        let bloom = theme.shape.bloom
        if glow, bloom > 0 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: cell * 0.8 * bloom))
                layer.fill(all, with: .color(lit))
            }
        }
        // The still lamps in one fill, as they were before there was a chase,
        // and only the seventeen under the trail painted one at a time.
        context.fill(still, with: .color(lit))
        for (dot, k) in driven {
            context.fill(dot, with: .color(lamp(driven: k)))
        }
    }

    /// The board's own lit colour, driven towards white.
    ///
    /// Towards white and not towards `board.highlight`: the highlight is the
    /// meter's warning amber in most themes, and a gold head sweeping a blue
    /// mark reads as a second colour rather than as the same lamps burning
    /// harder. The website takes its head to `#EAF6FF`, which is the lit
    /// colour with the hue nearly washed out of it — so this stops short of
    /// pure white by the same margin, and every theme keeps a trace of itself
    /// in the brightest dot.
    ///
    /// Built as a colour rather than mixed through `ThemeColor`, which would
    /// format a hex string for every dot of every frame.
    private static let peak: Double = 0.85

    private func lamp(driven k: Double) -> Color {
        let base = theme.board.lit
        let t = min(max(k, 0), 1) * Self.peak
        return Color(
            .sRGB,
            red: base.red + (1 - base.red) * t,
            green: base.green + (1 - base.green) * t,
            blue: base.blue + (1 - base.blue) * t
        )
    }

    // MARK: - Font

    static let height = 7

    /// `true` where a cell is lit. Characters are 5 wide with one blank column
    /// between them, so every row of the same length lines up as a column.
    static func bitmap(for text: String) -> [[Bool]] {
        let width = max(0, text.count * 6 - 1)
        var rows = Array(repeating: Array(repeating: false, count: width), count: height)
        for (index, character) in text.uppercased().enumerated() {
            let glyph = font[character] ?? font[" "]!
            for (row, line) in glyph.enumerated() {
                for (column, pixel) in line.enumerated() where pixel == "#" {
                    let x = index * 6 + column
                    if x < width { rows[row][x] = true }
                }
            }
        }
        return rows
    }

    private static let font: [Character: [String]] = [
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#...#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        ":": [".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", "..#..", "..#.."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."]
    ]
}

extension String {
    /// Pads to a fixed cell count so board rows line up as columns.
    func column(_ width: Int) -> String {
        count >= width ? String(prefix(width)) : self + String(repeating: " ", count: width - count)
    }
}
