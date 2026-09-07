import AppKit
import OcarinaTerminalContext
import SwiftUI

/// What the terminal is drawn on.
///
/// It was one flat colour, and a flat colour behind monospaced text is a text
/// field. Every other surface in this window is lit from somewhere and sits in
/// the theme; the largest one was the only one that did neither, so a Sakura
/// window came out pink down both sides and plain dark in the middle.
///
/// Four layers, none of which you are meant to look at:
///
/// - the bed colour, at the theme's own opacity, which is the only thing
///   between the text and the window's glass and is left exactly as it was;
/// - a wash of the accent falling from the top-left, so the surface has a
///   direction and belongs to the same light as the panels beside it;
/// - the board's dot grid, which is the one thing that makes this Ocarina's
///   terminal rather than a terminal;
/// - a rail across the top carrying what the tab is doing.
///
/// Everything here is under the text and stays under it. A terminal's job is to
/// be read, so none of it goes near the bed colour itself, which carries the
/// contrast the whole app is checked against — the grid is drawn in the board's
/// *unlit* dot, which is the colour that is already sitting behind every word
/// on the empty screen, and the vignette darkens towards the window's own
/// ground rather than towards black.
struct TerminalBed: View {
    @Environment(\.theme) private var theme

    /// What the tab in front of you is doing. Nil while nothing is selected.
    let activity: TabActivity?

    /// The dot grid's spacing and size.
    ///
    /// Tighter and heavier than the first attempt, which was measured in
    /// hundredths and came out as a surface you had to be told was there. The
    /// grid is the one thing that makes this Ocarina's terminal rather than a
    /// terminal, and a texture nobody can see is not doing that job.
    ///
    /// Still wider and fainter than the board's own matrix: the empty state's
    /// dots are the thing you are reading, and these are the paper under
    /// something else. The pitch stays clear of any plausible line height, so
    /// the rows of dots never come into step with the rows of text.
    private static let pitch: CGFloat = 6
    private static let dot: CGFloat = 1.9

    var body: some View {
        ZStack {
            // Untouched. This carries the contrast the whole app is checked
            // against, and it is not a place to put a mood.
            theme.chrome.bed.color
                .opacity(theme.chrome.bedOpacity)

            Image(nsImage: DotGrid.tile(
                NSColor(theme.board.unlit.color),
                pitch: Self.pitch,
                dot: Self.dot
            ))
            .resizable(resizingMode: .tile)

            // A light source. Falling to clear by the middle of the card, so
            // the bottom of a long scrollback is not a different colour from
            // the top of it.
            LinearGradient(
                colors: [theme.chrome.accent.color.opacity(0.11), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            // And the edges falling away from it. This is what stops the grid
            // reading as a pattern: it is strongest where you are working and
            // gone by the corners.
            RadialGradient(
                colors: [.clear, theme.ground.color.opacity(0.62)],
                center: .center,
                startRadius: 120,
                endRadius: 620
            )
        }
        .overlay(alignment: .top) { rail }
        .allowsHitTesting(false)
    }

    /// A lit rail across the top of the card, in the colour of what the tab is
    /// doing.
    ///
    /// The same four colours the status dots use, so amber means the same
    /// thing three feet from the screen as it does in the tab list. It earns
    /// the space by being the one signal you can take in without looking at
    /// it — a long build turns the top of your terminal amber and back again,
    /// and you never had to find the dot.
    ///
    /// Faded out at both ends rather than run edge to edge: a full-width line
    /// in a saturated colour is a border, and the card already has one.
    private var rail: some View {
        LinearGradient(
            colors: [.clear, railColour.opacity(railStrength), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.5)
        .animation(.easeOut(duration: 0.35), value: railStrength)
        .animation(.easeOut(duration: 0.35), value: activity)
    }

    private var railColour: Color {
        switch activity {
        case .running: theme.status.running.color
        case .succeeded: theme.status.succeeded.color
        case .failed: theme.status.failed.color
        case .idle, nil: theme.status.idle.color
        }
    }

    /// Idle is present but quiet. A tab waiting at a prompt is open and ready,
    /// not switched off — the same argument the status dots settled — but it
    /// is also the state a terminal is in almost all the time, and a rail at
    /// full strength for the ordinary case is a rail that says nothing.
    private var railStrength: Double {
        switch activity {
        case .running: 0.85
        case .failed: 0.8
        case .succeeded: 0.5
        case .idle, nil: 0.22
        }
    }
}

/// The tiled dot, rasterised once per colour.
///
/// A `Canvas` painting every dot is how `DotMatrix` does it, and that is right
/// for a panel of forty characters. A bed is tens of thousands of dots and
/// redraws with the window, so this is one tile repeated by the compositor
/// instead.
@MainActor
enum DotGrid {
    private static var cache: [String: NSImage] = [:]

    static func tile(_ colour: NSColor, pitch: CGFloat, dot: CGFloat) -> NSImage {
        let key = "\(colour.hashValue)-\(pitch)-\(dot)"
        if let cached = cache[key] { return cached }

        let image = NSImage(size: CGSize(width: pitch, height: pitch))
        image.lockFocus()
        colour.setFill()
        // Centred in the tile, so the grid does not run up against whatever
        // the bed is clipped to.
        let inset = (pitch - dot) / 2
        NSBezierPath(ovalIn: CGRect(x: inset, y: inset, width: dot, height: dot)).fill()
        image.unlockFocus()

        cache[key] = image
        return image
    }
}
