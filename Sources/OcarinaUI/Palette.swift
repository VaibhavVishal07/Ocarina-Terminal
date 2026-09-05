import SwiftUI

/// The colours the departure board is built from, which are the only colours
/// in the app that were ever chosen rather than inherited.
///
/// They lived as private constants inside `EmptyStateView`, which was fine
/// while the board was the only thing using them. It is not: the keep-awake
/// switch is tinted from here too, so the one saturated thing in the window
/// while you are working is the same blue as the one thing you see before you
/// start. Sharing the constant is the point — a second copy of the same
/// numbers is not a theme, it is two things that happen to agree today.
enum Palette {
    /// The lit cell. The app's signature: "OCARINA" on the board is this.
    static let lit = Color(red: 0.22, green: 0.76, blue: 1.0)
    /// A lit cell on a secondary line, dimmed rather than greyed.
    static let litDim = Color(red: 0.13, green: 0.42, blue: 0.58)
    /// An unlit cell, still visible behind the words — that is what makes a
    /// dot-matrix board read as a board and not as text.
    static let unlit = Color(red: 0.098, green: 0.110, blue: 0.133)
    /// Behind the board.
    static let backdrop = Color(red: 0.024, green: 0.027, blue: 0.035)
    /// The board's other colour: what a cell does under the pointer.
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.22)
}
