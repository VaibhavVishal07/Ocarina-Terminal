import OcarinaTerminalContext

/// The menu bar item: one cell of a departure board, and the four things it can
/// be showing.
///
/// This replaced a board that set the whole line — `STILL GOING`, `BACK TO
/// YOU`, `STOPPED 127` — in the app's own 5x7 alphabet, and then a little face
/// drawn on the same grid. The first was right about the language and cost 136
/// points of menu bar to say something too small to read. The second was
/// legible and was a face, which is a character from nowhere: it had no more to
/// do with this app than with any other.
///
/// A split-flap cell has both. It is the object the rest of the app is already
/// made of — the wordmark, the landing screen, the token meter are all lamps on
/// a departure board — and it says the four states by doing what a board does:
/// sit blank, turn, land on something, or show a cross.
///
/// **The seam is the whole idea.** A split-flap card is cut across its middle,
/// and that line has to be visible in every state or this is a box that fills
/// up. So it is drawn as a lit line when the cell is empty and as a dark gap
/// when the cell is full — the same hinge, taking whichever value contrasts
/// with what is around it. Row 2 is the seam and nothing else is ever drawn
/// there.
///
/// The words did not go anywhere. They are the accessibility label and the
/// tooltip, and the theme's own line — with the exit code on it — is one click
/// down in the menu. See `ActivityStatusItem.title(for:)`.
enum ActivityCard: Equatable, CaseIterable {
    /// Nothing has been asked in this tab yet. An empty cell: the frame and the
    /// seam, and nothing on the card.
    case ready
    /// An ask that has not come back. The card turns — see `turn`.
    case working
    /// The agent stopped and it is your move.
    ///
    /// The card lands on the app's own O. Not a tick, which was the most
    /// readable of the seven things tried here and the only one that grades the
    /// work: an agent stopping means it stopped talking, not that it managed
    /// what you asked, and that is why the words up here say *back to you* and
    /// never *done*. A ring makes no claim. It also gives the menu bar the one
    /// mark that says whose it is.
    case backToYou
    /// It rang. An exclamation, and the seam falls inside the mark's own gap —
    /// the one plate where the fold is not something to draw around.
    case needsYou
    /// It exited non-zero. A cross, cut by the seam. The number is in the
    /// tooltip; a five-lamp card has no way to say 127 and no business trying.
    case stopped

    init(_ activity: TabActivity) {
        switch activity {
        case .idle: self = .ready
        case .running: self = .working
        case .succeeded: self = .backToYou
        case .needsYou: self = .needsYou
        case .failed: self = .stopped
        }
    }

    /// Seven by seven, and square.
    ///
    /// A real split-flap card is taller than it is wide, and this was five by
    /// seven for a while on exactly that reasoning. In a menu bar it is wrong:
    /// every other item up there — Wi-Fi, battery, Bluetooth, the Control
    /// Centre toggles — sits in a square, and a tall narrow one reads as
    /// something that has been squeezed rather than as something drawn to fit.
    /// The proportion of the real object is worth less than sitting properly in
    /// the row it lives in.
    ///
    /// Widening rather than shortening, because the two states that are marks
    /// rather than fills need the room. It was five by five once, and there a
    /// cross has its crossing point *on* the seam — the one row nothing may be
    /// drawn on — so it came out as eight loose dots, and a ring sat one lamp
    /// inside the frame the whole way round and read as a second border. Seven
    /// by seven gives each half three rows and the mark a proper diagonal.
    static let columns = 7
    static let rows = 7
    /// The row the hinge runs along. Nothing is ever drawn here — what makes the
    /// seam visible on a full card is that it is the one dark line across it.
    static let seam = 3

    /// The still card for this state. `#` is a lit lamp, `.` a dark cell.
    ///
    /// `working` is a still of the turn's first frame, for the one moment before
    /// the timer takes over — see `turn`.
    var plate: [String] {
        switch self {
        case .ready:
            [".......",
             ".......",
             ".......",
             "#######",
             ".......",
             ".......",
             "......."]
        case .working:
            Self.turn[0]
        case .backToYou:
            ["..###..",
             ".#...#.",
             "#.....#",
             ".......",
             "#.....#",
             ".#...#.",
             "..###.."]
        case .needsYou:
            ["..###..",
             "..###..",
             "..###..",
             ".......",
             ".......",
             "..###..",
             "......."]
        case .stopped:
            ["#.....#",
             ".#...#.",
             "..#.#..",
             ".......",
             "..#.#..",
             ".#...#.",
             "#.....#"]
        }
    }

    /// The turn, five frames: the card stands, folds through the seam, passes
    /// edge-on, lands on the bottom half, and rests there before the next one
    /// comes over the top.
    ///
    /// Frames rather than a chase, which is what every other moving thing in
    /// this app is. A chase is a lamp brightening and dimming — right for a
    /// mark that is *lit*, and wrong for a card, which does not glow, it moves.
    /// A departure board clacks.
    ///
    /// Five and not six. A sixth frame returning to the seam line would show
    /// the resting card once a pass, and the resting card is what `ready`
    /// looks like — a working item that flickers through "nothing asked" six
    /// times a second is worse than one that simply loops.
    static let turn: [[String]] = [
        // Standing: the card up, filling the top half.
        ["#######",
         "#######",
         "#######",
         ".......",
         ".......",
         ".......",
         "......."],
        // Folding: most of it already through.
        [".......",
         ".......",
         "#######",
         ".......",
         ".......",
         ".......",
         "......."],
        // Edge-on. Only the frame is drawn for this one frame, which is what a
        // card looks like halfway round.
        [".......",
         ".......",
         ".......",
         ".......",
         ".......",
         ".......",
         "......."],
        // Coming down the other side.
        [".......",
         ".......",
         ".......",
         ".......",
         "#######",
         ".......",
         "......."],
        // Landed, filling the bottom half.
        [".......",
         ".......",
         ".......",
         ".......",
         "#######",
         "#######",
         "#######"],
    ]

    /// How long one frame of the turn is up.
    ///
    /// 120ms a frame is 600ms to the flip, which is the rate a real board runs
    /// at and slow enough that the item costs eight repaints a second rather
    /// than the thirty the chase it replaced did.
    static let flipInterval: Double = 0.12
}
