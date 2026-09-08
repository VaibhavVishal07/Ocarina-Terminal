import AppKit
import OcarinaTerminalContext

/// What the agent in front of you is doing, in the menu bar beside the Wi-Fi.
///
/// This slot used to hold the token figure, and the two swapped places. The
/// token reading is a question you ask once an hour and it belongs on a card
/// you can look at deliberately, which is where it is again. Whether the thing
/// you asked for is still going is a question you have *while you are looking
/// at something else* — a browser, a design tool, someone else's screen — and
/// the menu bar is the only surface Ocarina owns that is visible from there.
///
/// It replaced a drop out of the notch that said the same thing by taking over
/// the most valuable strip of screen on the Mac for three and a half seconds.
/// A status item says it for as long as it is true and costs nobody a frame of
/// what they were doing.
///
/// What it shows is one cell of a departure board — see `ActivityCard` for why
/// it is a picture and not the sentence it used to be, and why it is that
/// picture. The words behind it are the house line, on
/// the tooltip and the accessibility label; the theme's own wording is in the
/// menu underneath. See `title(for:)` for why they are not the same sentence.
/// What either one *means* is fixed by the state it came from, so a theme can
/// be as arch as it likes about a failure in the menu without being able to
/// make one read as a success.
@MainActor
public final class ActivityStatusItem: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var spinner: Timer?
    /// The last thing we were told, kept because the menu is built from it on
    /// the way open rather than rebuilt every time the reading is refreshed.
    private var reading: Reading?
    /// Which frame of the turn is showing. Only moves while something is
    /// running; the other three states are still cards.
    private var frame = 0


    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public override init() { super.init() }

    /// Everything the item needs, resolved by the caller.
    ///
    /// A struct rather than five arguments because all five change together —
    /// the state, what it is about, and the theme saying it are one reading of
    /// one moment, and an update that took them separately could draw a
    /// Matrix sentence about a task from the tab before last.
    public struct Reading: Equatable {
        /// Nil takes the item out of the menu bar: there is no tab open, so
        /// there is nothing true to say and a menu bar item that says nothing
        /// is the most expensive furniture on the Mac.
        public let activity: TabActivity?
        /// What is being worked on, already summarised. Nil is fine — it only
        /// ever adds detail to a line that reads without it.
        public let task: String?
        /// The token window, for the menu underneath. The figure left this
        /// button when the card took it back; it stays one click away rather
        /// than being deleted, because a menu costs nothing until it is opened.
        public let usage: UsageWindow?
        public let speech: Theme.Speech

        public init(
            activity: TabActivity?,
            task: String?,
            usage: UsageWindow?,
            speech: Theme.Speech
        ) {
            self.activity = activity
            self.task = task
            self.usage = usage
            self.speech = speech
        }
    }

    public func update(_ reading: Reading) {
        guard let activity = reading.activity else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            // Forgotten, not merely hidden: the next item to go up compares
            // its line against this, and a stale one would leave the new item
            // in the menu bar with no title at all.
            self.reading = nil
            stopTurning()
            return
        }

        let item = self.item ?? make()
        self.item = item

        // Nothing said anything new. Returning here is not only a saving: the
        // spinner is a timer that this would otherwise tear down and rebuild
        // on every fifteen-second usage refresh, which is a visible stutter in
        // something whose whole job is to turn smoothly.
        let wasShowing = self.reading.map { ActivityCard($0.activity ?? .idle) }
        self.reading = reading

        // The words go up whatever the face is doing, and they carry the task
        // and the exit code the face has no way to draw. Set before the guard:
        // the face for `.failed(1)` and `.failed(127)` is the same picture, and
        // the reading behind it is not.
        let words = Self.tooltip(for: activity, reading: reading)
        item.button?.toolTip = words
        item.button?.setAccessibilityLabel(words)

        let card = ActivityCard(activity)
        guard card != wasShowing else { return }

        // The turn owns the image while something is running, so drawing it
        // here as well would fight the timer for the same picture.
        if activity.isRunning {
            startTurning()
        } else {
            stopTurning()
            item.button?.image = Self.glyph(card)
        }
    }

    /// Built on the way open, not held.
    ///
    /// The reading behind it is refreshed every fifteen seconds and the menu
    /// carries a countdown that has to be right when it is read — so assigning
    /// a freshly built `NSMenu` on each refresh would either show a stale
    /// countdown or swap the menu out from under somebody who has it open.
    /// This is the delegate AppKit provides for exactly that.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let reading, let activity = reading.activity else { return }
        menu.addItem(Self.row(Self.line(for: activity, speech: reading.speech)))
        if let task = reading.task, !task.isEmpty {
            menu.addItem(Self.row(task))
        }

        guard let usage = reading.usage else { return }
        menu.addItem(.separator())
        menu.addItem(Self.row("\(usage.tokens.formatted()) tokens used"))
        menu.addItem(Self.row("Window opened \(Self.clock.string(from: usage.startedAt))"))
        menu.addItem(Self.row("Resets in \(Self.countdown(to: usage.resetsAt, from: Date()))"))
        menu.addItem(.separator())
        // Said out loud rather than left for someone to assume. A meter that
        // looks like it knows the allowance, and does not, is worse than one
        // that admits it.
        menu.addItem(Self.row("Tokens remaining are not shown: nothing on"))
        menu.addItem(Self.row("this Mac records the size of the allowance."))
    }

    // MARK: - The words

    /// What the item says when it is asked — on hover, and to VoiceOver.
    ///
    /// Not the theme's line, and this is the one place that difference is
    /// worth the extra function. The menu bar is the only surface Ocarina
    /// owns that is read from *outside* Ocarina — no window, no icon, no
    /// context — and the two things somebody glancing up wants from it are
    /// which app is talking and what it is doing. A theme being arch there
    /// costs them both: Steel used to put "Under load" in the menu bar, which
    /// reads as a warning about the Mac rather than a report about a build.
    ///
    /// The words are the app's, in the same form for every theme. The
    /// register is not lost — it is one click down, in `menuNeedsUpdate`,
    /// where you have already pressed something belonging to Ocarina and know
    /// whose voice you are reading.
    ///
    /// They answer the question somebody actually has up here, which is not
    /// "what state is this in" but "is the thing I asked for still going, and
    /// is it waiting on me". They were the state's own names for a release —
    /// Working, Idle, Done — and each was a label for a value in an enum
    /// rather than an answer.
    ///
    /// Sentence case, and set in whatever font is asking. It was uppercase in
    /// the app's 5x7 alphabet for as long as it was painted on a board, which
    /// is a constraint the board imposed and not one the words ever had: a
    /// grid with no descenders wants capitals, and VoiceOver does not.
    ///
    /// The app's name is not in front of them, because `tooltip(for:reading:)`
    /// puts it there once and these are what follows the dash.
    ///
    /// - **Still going** — your ask has not come back yet.
    /// - **Back to you** — the agent stopped and it is your move. Not "done":
    ///   the agent stopping does not mean it managed what you asked, and the
    ///   word up here has to be one this can support.
    /// - **Ready** — nothing has been asked in this tab yet.
    /// - **Stopped (n)** — it exited, and here is the number. The face cannot
    ///   draw a number; this is where the number lives.
    nonisolated static func title(for activity: TabActivity) -> String {
        switch activity {
        case .idle: "Ready"
        case .running: "Still going"
        case .succeeded: "Back to you"
        // Same rule as `line`: the code is appended here, not written by a
        // theme, so a failure in the menu bar always carries its number.
        case let .failed(code): "Stopped (\(code))"
        }
    }

    /// The theme's line for this state, for the menu and the tooltip.
    ///
    /// `nonisolated` and `static` so the tests can read it without a menu bar
    /// to hang an item from: what a state is *called* is the part worth
    /// pinning down, and it does not need AppKit to be true.
    nonisolated static func line(for activity: TabActivity, speech: Theme.Speech) -> String {
        switch activity {
        case .idle: speech.clear
        case .running: speech.working
        case .succeeded: speech.done
        // The code goes here rather than in the theme's line, so a theme
        // cannot write a failure that does not carry its number.
        case let .failed(code): "\(speech.stopped) (\(code))"
        }
    }

    /// The long form, for the tooltip and the accessibility label — the
    /// sentence the face is the short version of, with the task named when
    /// there is one.
    ///
    /// It names the app because this is the one surface Ocarina owns that is
    /// read from outside Ocarina, and a picture of a face has nothing to say
    /// whose it is. That was true of the board too; the board answered it by
    /// being drawn in the app's own alphabet, which a face cannot do.
    nonisolated static func tooltip(for activity: TabActivity, reading: Reading) -> String {
        let line = line(for: activity, speech: reading.speech)
        guard let task = reading.task, !task.isEmpty else { return "Ocarina — \(line)" }
        return "Ocarina — \(line): \(task)"
    }

    // MARK: - The card

    /// One card, drawn as lamps inside a frame.
    ///
    /// The menu bar used to be a system-font string with a braille spinner in
    /// front of it and an SF Symbol beside it — three different alphabets for
    /// one reading, none of them Ocarina's. Then it was the whole line set in
    /// the app's own 5x7 grid, which fixed the alphabet and cost 136 points of
    /// menu bar to say something you could not read at that size. This is the
    /// same lamps at a size the bar has room for: a five by seven cell, twelve
    /// and a half points by sixteen and a half, with a frame round them.
    ///
    /// A template image, so the menu bar tints it. A template has no colour of
    /// its own; what it has is how much of the bar's own ink each lamp asks
    /// for, which turns out to be the right model for a lamp anyway.
    ///
    /// Unlit cells are not painted. The face this replaced drew its whole grid
    /// faintly, because a face made of five loose lamps needs the dark field to
    /// read as a panel — a card does not: it has a frame, and the frame is what
    /// says where the object stops.
    ///
    /// Built with a drawing handler rather than `lockFocus`, so it is
    /// resolution-independent: AppKit re-runs the block at whatever scale it is
    /// being drawn at. `lockFocus` rasterises once, at the deepest attached
    /// screen's scale, and hands back a bitmap — so the 0.35pt gap between two
    /// lamps landed wherever it landed on the pixel grid, and a filled row that
    /// should read as a bar came out as a line of separated dots. It also made
    /// the item's crispness depend on which display happened to be plugged in
    /// when it was drawn.
    static func glyph(_ card: ActivityCard, turn frameIndex: Int? = nil) -> NSImage {
        let plate = frameIndex.map { ActivityCard.turn[$0 % ActivityCard.turn.count] }
            ?? card.plate
        let size = NSSize(
            width: CGFloat(ActivityCard.columns) * pitch - gap + inset * 2,
            height: CGFloat(ActivityCard.rows) * pitch - gap + inset * 2
        )
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor(white: 0, alpha: lit).setFill()
            for (row, line) in plate.enumerated() {
                for (column, cell) in line.enumerated() where cell == "#" {
                    let box = NSRect(
                        x: inset + CGFloat(column) * pitch,
                        // The plate's first row is the top, and this context's
                        // origin is the bottom left.
                        y: size.height - inset - CGFloat(row) * pitch - Self.cell,
                        width: Self.cell,
                        height: Self.cell
                    )
                    // Squarer than the face's lamps were. A card is a surface,
                    // and at a 0.3 radius this little gap left a row of
                    // pinholes down what should read as one bar.
                    NSBezierPath(roundedRect: box,
                                 xRadius: Self.cell * 0.18,
                                 yRadius: Self.cell * 0.18).fill()
                }
            }

            // The frame, last, so it sits over anything that reaches the edge.
            let border = NSBezierPath(
                roundedRect: NSRect(x: stroke / 2, y: stroke / 2,
                                    width: size.width - stroke,
                                    height: size.height - stroke),
                xRadius: 3, yRadius: 3
            )
            border.lineWidth = stroke
            NSColor(white: 0, alpha: framing).setStroke()
            border.stroke()
            return true
        }
        // Tinted by the menu bar, so it inverts with it the way every system
        // item does rather than staying one colour through both.
        image.isTemplate = true
        image.accessibilityDescription = "Ocarina"
        return image
    }

    /// A menu bar is about twenty-two points tall and this has to sit in it
    /// with room above and below: seven rows at a 2.05pt pitch is 14 points,
    /// and the frame takes it to **16.6 points square**. Square because every
    /// other item in a menu bar is — see `ActivityCard.columns`.
    ///
    /// **The lamps are thick and the gaps between them are thin** — 1.7 against
    /// 0.35, which fills 83% of the pitch where the face this replaced filled
    /// 70%. That is the difference between a row of dots and a bar. A face is
    /// made of separate lamps and wants the dark between them; a card is a
    /// surface, and every state here is mostly filled rows, so a filled row has
    /// to read as very nearly solid.
    private nonisolated static let cell: CGFloat = 1.7
    private nonisolated static let gap: CGFloat = 0.35
    private nonisolated static var pitch: CGFloat { cell + gap }
    /// How far the frame sits outside the lamps.
    private nonisolated static let inset: CGFloat = 1.3
    /// And how heavy it is drawn. A hairline read as a smudge beside lamps this
    /// thick, which made the cell look unfinished rather than framed.
    private nonisolated static let stroke: CGFloat = 1.15

    /// A lit lamp, and the frame around it. The frame is quieter than the
    /// lamps: it is the thing that never changes, so it should not be the thing
    /// that catches the eye.
    private nonisolated static let lit: Double = 0.92
    private nonisolated static let framing: Double = 0.55

    // MARK: - The turn

    private func startTurning() {
        spinner?.invalidate()
        // Drawn once immediately: a timer that fires in 120ms would otherwise
        // leave the previous state's card up for an eighth of a second you can
        // see.
        frame = 0
        draw()
        let timer = Timer(timeInterval: ActivityCard.flipInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw() }
        }
        // `.common`, not the default mode: a status item stops updating while
        // a menu is open or a window is being dragged if the timer only runs
        // in the default run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        spinner = timer
    }

    /// One frame of the turn.
    ///
    /// The braille spinner this replaced was a good answer to a different
    /// question — every tool in a terminal turns one, so it needed no
    /// explaining — but it sat in front of a system-font string and made the
    /// reading three alphabets wide. The card says the same thing by turning,
    /// which is what a departure board does and what the app is built out of.
    ///
    /// Eight repaints a second rather than the chase's thirty, and each is five
    /// filled rows rather than sixty-five lamps of alpha arithmetic.
    private func draw() {
        item?.button?.image = Self.glyph(.working, turn: frame)
        frame = (frame + 1) % ActivityCard.turn.count
    }

    private func stopTurning() {
        spinner?.invalidate()
        spinner = nil
    }

    private func make() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Nothing but the face. There is no title to sit beside it any more,
        // and `.squareLength` is what keeps the item the same width through all
        // four states — every face is the same plate, so the item no longer
        // resizes when a run ends and nothing to its left in the menu bar
        // shifts under it.
        item.button?.imagePosition = .imageOnly
        // Empty, and filled by `menuNeedsUpdate` on the way open.
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    private static func row(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    nonisolated static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
