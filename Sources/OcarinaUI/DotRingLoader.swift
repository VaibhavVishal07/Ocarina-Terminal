import SwiftUI

/// The spinner: the app's own mark, lighting round.
///
/// The icon is a five-by-five matrix with an O punched through it, so the ring
/// of twelve is already the shape somebody has been looking at in the dock all
/// day. Turning that ring is the only loader this app can have that is not
/// borrowed from somewhere else.
///
/// It is drawn rather than animated by SwiftUI on purpose. Twelve views each
/// carrying a `repeatForever` with its own `delay` is the pattern that failed
/// in `StatusDot` — the value the animation watches is set once and never
/// changes again, so nothing ever runs. A timeline carries its own clock, and
/// a `Canvas` draws twelve dots in one pass rather than laying out twelve
/// views sixty times a second.
struct DotRingLoader: View {
    let colour: Color
    /// The unlit cells, so the ring reads as a matrix with something moving
    /// through it rather than as dots appearing out of nothing.
    let unlit: Color
    var side: CGFloat = 22

    /// One turn. Slow enough not to nag, fast enough to be obviously moving —
    /// this is the same judgement the old pulse was making at 0.9s, and a
    /// revolution has further to go than a fade.
    private static let period: Double = 1.15
    /// How far the tail reaches behind the head, as a fraction of the ring.
    /// Short and it strobes; long and every dot is half lit and nothing moves.
    private static let tail: Double = 0.42

    /// Clockwise from the top-left of the ring, in a 5x5 grid.
    private static let ring: [(row: Int, column: Int)] = [
        (0, 1), (0, 2), (0, 3),
        (1, 4), (2, 4), (3, 4),
        (4, 3), (4, 2), (4, 1),
        (3, 0), (2, 0), (1, 0),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { drawing, size in
                let pitch = size.width / 5
                let diameter = pitch * 0.74
                let head = (context.date.timeIntervalSinceReferenceDate / Self.period)
                    .truncatingRemainder(dividingBy: 1)

                for (index, cell) in Self.ring.enumerated() {
                    let seat = Double(index) / Double(Self.ring.count)
                    // How far this dot sits behind the head, wrapped, so the
                    // tail crosses the seam instead of snapping at it.
                    var behind = head - seat
                    if behind < 0 { behind += 1 }
                    let level = max(0, 1 - behind / Self.tail)

                    let box = CGRect(
                        x: CGFloat(cell.column) * pitch + (pitch - diameter) / 2,
                        y: CGFloat(cell.row) * pitch + (pitch - diameter) / 2,
                        width: diameter,
                        height: diameter
                    )
                    let dot = Path(ellipseIn: box)
                    drawing.fill(dot, with: .color(unlit))
                    if level > 0 {
                        drawing.fill(dot, with: .color(colour.opacity(level)))
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
