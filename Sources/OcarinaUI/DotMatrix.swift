import SwiftUI

/// A 5x7 dot-matrix panel, drawn the way a departure board is built: every cell
/// in the grid is painted, dark when it is off, so the matrix stays visible
/// behind the words instead of the text floating on black.
struct DotMatrixText: View {
    let text: String
    var cell: CGFloat = 3.4
    var gap: CGFloat = 1.2
    var lit: Color
    var unlit: Color
    /// Lit cells bloom, the way an LED board does behind its diffuser.
    var glow: Bool = true

    private var pitch: CGFloat { cell + gap }
    private var columns: Int { max(0, text.count * 6 - 1) }

    var body: some View {
        Canvas { context, _ in
            let bits = Self.bitmap(for: text)
            var on = Path(), off = Path()
            for row in 0..<Self.height {
                for column in 0..<columns {
                    let box = CGRect(
                        x: CGFloat(column) * pitch,
                        y: CGFloat(row) * pitch,
                        width: cell,
                        height: cell
                    )
                    let dot = Path(roundedRect: box, cornerRadius: cell * 0.3)
                    if bits[row][column] { on.addPath(dot) } else { off.addPath(dot) }
                }
            }
            context.fill(off, with: .color(unlit))
            if glow {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: cell * 0.8))
                    layer.fill(on, with: .color(lit))
                }
            }
            context.fill(on, with: .color(lit))
        }
        .frame(
            width: CGFloat(columns) * pitch - gap,
            height: CGFloat(Self.height) * pitch - gap
        )
        .accessibilityLabel(text)
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
