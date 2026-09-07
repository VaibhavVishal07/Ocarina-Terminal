import SwiftUI

/// The small thing a theme has drifting on its landing screen.
///
/// Themes used to carry a background motif — petals, leaves, embers, rain —
/// and it was taken out of the renderer and out of the format. The reason it
/// failed is worth keeping hold of, because it is not "motifs are bad": read at
/// one row it was texture, and read down a column of tabs it was litter behind
/// the thing you were trying to scan. It was drawn behind content.
///
/// This is the one surface in the app with no content to be behind. The landing
/// screen is empty by definition — that is its whole name — so a handful of
/// petals crossing it is the only thing on screen that is not either the app's
/// name or a button, and there is nothing for it to get in the way of. It does
/// not appear anywhere else, and there is no field for making it appear
/// anywhere else.
///
/// Two themes have none. Mono is a theme about not doing this, and High
/// Contrast exists for people for whom moving decoration behind text is the
/// problem rather than the charm — for both of them the honest value is
/// `nil`, not a quieter setting.
public enum Trinket: String, Codable, Sendable, CaseIterable {
    /// Falling, swaying, turning over as they go.
    case petals
    /// The same fall, heavier and slower — a leaf has more air under it.
    case leaves
    /// Rising, brightening and going out.
    case embers
    /// Rising, and wobbling on the way up.
    case bubbles
    /// Going nowhere. Fading in and out where they are.
    case stars
    /// Falling in straight fast lines, in columns.
    case rain
    /// Barely moving at all: motes turning over in still air.
    case dust
    /// Rising and fading, the one that is the app's own.
    case notes

    /// Which way the thing goes, which is most of what it is.
    enum Motion { case falling, rising, still, streaking }

    var motion: Motion {
        switch self {
        case .petals, .leaves, .rain: .falling
        case .embers, .bubbles, .notes: .rising
        case .stars, .dust: .still
        }
    }

    /// Seconds for one to cross the screen. A trinket that crosses in four
    /// seconds is weather; these are somewhere between twelve and forty, which
    /// is slow enough that you notice one has moved rather than watching it
    /// move.
    var crossing: Double {
        switch self {
        case .rain: 2.2
        case .embers: 9
        case .bubbles: 11
        case .petals: 15
        case .notes: 13
        case .leaves: 22
        case .dust: 40
        case .stars: 1 // Unused: still things do not cross.
        }
    }

    /// How many are on screen at once. Sparse on purpose — the number where
    /// you would have to count them is the number where it is a screensaver.
    var count: Int {
        switch self {
        case .rain: 26
        case .dust, .stars: 22
        case .petals, .leaves: 14
        case .embers: 16
        case .bubbles, .notes: 11
        }
    }

    /// How far it drifts sideways on the way, in points.
    var sway: Double {
        switch self {
        case .petals: 34
        case .leaves: 46
        case .embers: 14
        case .bubbles: 9
        case .notes: 18
        case .dust: 22
        case .rain, .stars: 0
        }
    }

    /// The long side of one, in points.
    var size: Double {
        switch self {
        case .rain: 13
        case .leaves: 9
        case .petals: 7
        case .notes: 7
        case .embers: 3.4
        case .bubbles: 6
        case .stars: 5
        case .dust: 2.4
        }
    }

    /// How hard it is drawn at its brightest.
    ///
    /// All of these are under a third. The landing screen has four icons and a
    /// button on it that somebody is trying to choose between, and the moment a
    /// petal is as strong as the thing it crosses behind, the petal has won an
    /// argument it should not have been in.
    var strength: Double {
        switch self {
        case .embers: 0.30
        case .rain: 0.20
        case .stars: 0.28
        case .petals, .notes: 0.24
        case .leaves: 0.22
        case .bubbles: 0.18
        case .dust: 0.16
        }
    }

    /// One of them, drawn at the origin, `size` across.
    ///
    /// Shapes rather than glyphs: at seven points a character is a smudge, and
    /// these have to read as *something* from the corner of your eye or they
    /// are just noise on the backdrop.
    func path(size length: Double) -> Path {
        var path = Path()
        let box = CGRect(x: -length / 2, y: -length / 2, width: length, height: length)
        switch self {
        case .petals:
            // A leaf-lens: two arcs meeting at a point at each end.
            path.move(to: CGPoint(x: 0, y: -length / 2))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: length / 2),
                control: CGPoint(x: length * 0.62, y: 0)
            )
            path.addQuadCurve(
                to: CGPoint(x: 0, y: -length / 2),
                control: CGPoint(x: -length * 0.16, y: 0)
            )
        case .leaves:
            path.move(to: CGPoint(x: 0, y: -length / 2))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: length / 2),
                control: CGPoint(x: length * 0.5, y: 0)
            )
            path.addQuadCurve(
                to: CGPoint(x: 0, y: -length / 2),
                control: CGPoint(x: -length * 0.5, y: 0)
            )
        case .embers, .dust:
            path.addEllipse(in: box)
        case .bubbles:
            path = Path(ellipseIn: box)
                .strokedPath(StrokeStyle(lineWidth: max(0.8, length * 0.14)))
        case .stars:
            path = SparkShape().path(in: box)
        case .rain:
            path.addRoundedRect(
                in: CGRect(x: -0.6, y: -length / 2, width: 1.2, height: length),
                cornerSize: CGSize(width: 0.6, height: 0.6)
            )
        case .notes:
            // A note head with a stem. Not an SF Symbol: this is drawn into a
            // `Canvas`, and a symbol there is an image resolve per particle
            // per frame.
            path.addEllipse(in: CGRect(
                x: -length * 0.45, y: length * 0.1,
                width: length * 0.55, height: length * 0.4
            ))
            path.addRect(CGRect(
                x: length * 0.02, y: -length * 0.5,
                width: max(0.9, length * 0.11), height: length * 0.8
            ))
        }
        return path
    }
}
