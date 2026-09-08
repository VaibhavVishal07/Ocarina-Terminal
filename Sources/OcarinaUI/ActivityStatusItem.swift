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
    /// The words currently up, so the turn can redraw the plate without
    /// re-deriving them and so a changed exit code still reaches the bar.
    private var lastWords = ""
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
    /// A struct rather than six arguments because all six change together —
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
        ///
        /// This is the *tooltip's* copy of the task. A tooltip is one line and
        /// has room for one, and the one worth naming there is the one the
        /// face is about. The menu underneath has room for the list.
        public let task: String?
        /// The tab's asks, oldest first, exactly as the panel has them —
        /// cleared line applied, better titles in.
        ///
        /// The menu carries them because the question the panel answers is one
        /// you have with Ocarina's window *behind* something else: you gave the
        /// agent five things across twenty minutes and cannot remember which of
        /// them it got to. The panel can only answer that once you have brought
        /// the window forward, which is the moment you least need to ask.
        ///
        /// The whole list, not the five that fit: `listing` decides how many a
        /// menu is worth, and `menuNeedsUpdate` says out loud how many it left
        /// off. A caller that trimmed first would leave the menu unable to.
        public let tasks: [AgentTask]
        /// The token window, for the menu underneath. The figure left this
        /// button when the card took it back; it stays one click away rather
        /// than being deleted, because a menu costs nothing until it is opened.
        public let usage: UsageWindow?
        public let speech: Theme.Speech

        public init(
            activity: TabActivity?,
            task: String?,
            tasks: [AgentTask],
            usage: UsageWindow?,
            speech: Theme.Speech
        ) {
            self.activity = activity
            self.task = task
            self.tasks = tasks
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

        // And the state, in words, beside the card.
        //
        // The card went up alone for a release, on the argument that eleven
        // characters of the app's own 5x7 alphabet is 136 points of menu bar —
        // wider than the clock, the Wi-Fi and the battery together — for a
        // reading you take in a fifth of a second. That was true of the *grid*
        // and not of the words: the same line set in the system font is a third
        // of that, and it is the font every other item up there is already set
        // in. A picture alone asks you to have learned four plates; a picture
        // with its name beside it teaches them and then keeps working when you
        // have.
        //
        // Set before the guard below, for the same reason the tooltip is: the
        // plate for `.failed(1)` and `.failed(127)` is one picture and the
        // words are not.
        // The words are part of the picture now — see `plate`. The button's
        // own title stays empty, or AppKit would set the same reading twice in
        // two different alphabets.
        item.button?.title = ""
        let board = Self.boardWords(for: activity)

        let card = ActivityCard(activity)
        // The words change on their own — `.failed(1)` and `.failed(127)` are
        // one card and two readings — so the guard cannot be on the card alone
        // the way it was when the words were a separate label.
        guard card != wasShowing || board != lastWords else { return }
        lastWords = board

        // The turn owns the image while something is running, so drawing it
        // here as well would fight the timer for the same picture.
        if activity.isRunning {
            startTurning()
        } else {
            stopTurning()
            item.button?.image = Self.plate(card, words: board)
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

        // The list, and not the one task above it as well. The row that used
        // to sit here was `selectedTaskTitle`, which is the newest open ask —
        // the first row of this list under another name. Two lines saying the
        // same thing with one of them unmarked reads as two different tasks.
        let listed = Self.listing(reading.tasks)
        if !listed.isEmpty {
            menu.addItem(.separator())
            for task in listed { menu.addItem(Self.taskRow(task)) }
            // Said rather than left to be assumed. A list that stops at five
            // with no sign it stopped is a list claiming the sixth ask was
            // never made.
            let rest = reading.tasks.count - listed.count
            if rest > 0 { menu.addItem(Self.row("and \(rest) more in the panel")) }
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
        // Not "Needs input", which reads as a form. This is the one state that
        // is about *you* rather than about the run, and the words up here are
        // meant to answer "is it waiting on me" in a glance.
        case .needsYou: "Needs you"
        // Same rule as `line`: the code is appended here, not written by a
        // theme, so a failure in the menu bar always carries its number.
        case let .failed(code): "Stopped (\(code))"
        }
    }

    /// The same reading, in the letters the board can draw.
    ///
    /// The menu bar sets its words in the app's own 5x7 alphabet now, and that
    /// alphabet is A–Z, 0–9 and a handful of marks — **no brackets**. So
    /// `Stopped (127)` cannot be set here; it would come out with two blank
    /// cells where the eye expects the number to start.
    ///
    /// Shorter than `title(for:)` as well, and deliberately. A matrix letter is
    /// six columns at the card's own pitch — about 10 points — so every word
    /// costs roughly three times what the system font charged for it. "Still
    /// going" would be 110 points of menu bar to say what the card is already
    /// saying by turning.
    nonisolated static func boardWords(for activity: TabActivity) -> String {
        switch activity {
        case .idle: "READY"
        case .running: "WORKING"
        case .succeeded: "DONE"
        case .needsYou: "NEEDS YOU"
        case let .failed(code): "STOPPED \(code)"
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
        case .needsYou: speech.needsYou
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

    // MARK: - The list

    /// How many asks the menu carries.
    ///
    /// Five, and the number is about the menu bar rather than about the list.
    /// This drops under the clock while you are looking at something else, so
    /// what it costs is the screen you were reading — a menu that ran to the
    /// twenty asks a long session accumulates would cover the window it is
    /// meant to save you from opening. Five is the depth you can take in
    /// without reading, and it is the same five the panel's own note names as
    /// the case it exists for: five things across twenty minutes.
    ///
    /// The rest are not hidden, they are counted — see `menuNeedsUpdate`.
    nonisolated static let listed = 5

    /// The last few asks, newest first.
    ///
    /// Newest first because the menu is read from the top and the ask you are
    /// waiting on is the last one you made. The panel reverses for the same
    /// reason; the two surfaces show the same list in the same order, which is
    /// what stops them reading as two different accounts of the tab.
    nonisolated static func listing(_ tasks: [AgentTask], limit: Int = listed) -> [AgentTask] {
        Array(tasks.suffix(limit).reversed())
    }

    /// What a row says to VoiceOver.
    ///
    /// The mark beside a row is a picture, and a picture is exactly nothing to
    /// a screen reader. Spoken, the state has to be a word — and it is the
    /// same word the state carries everywhere else in the app: an agent that
    /// stopped is *finished*, never done. See `AgentTask.State`.
    nonisolated static func spoken(_ task: AgentTask) -> String {
        "\(task.title) — \(task.state == .finished ? "finished" : "still going")"
    }

    /// One ask, marked with what became of it.
    ///
    /// The same two marks the panel uses, for the same reason: a tick is quiet
    /// and an open item is an empty box, so the eye lands on the row still
    /// outstanding rather than on the ones already dealt with. A menu item's
    /// own `state` would have drawn the tick for us and nothing at all for the
    /// open row, which inverts that.
    private static func taskRow(_ task: AgentTask) -> NSMenuItem {
        let item = row(task.title)
        let finished = task.state == .finished
        let mark = NSImage(
            systemSymbolName: finished ? "checkmark" : "square",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: 10,
                weight: finished ? .semibold : .regular
            )
        )
        mark?.isTemplate = true
        item.image = mark
        item.setAccessibilityLabel(spoken(task))
        return item
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

    /// The words, set in the board's alphabet.
    ///
    /// Same letters as the wordmark in the sidebar and the line on the empty
    /// state, so the one surface Ocarina owns *outside* its own window is
    /// written in the same hand as everything inside it. That was the argument
    /// the card was carrying alone; the words can carry it too now.
    ///
    /// A shade smaller than the card's lamps — `textCell` against `cell` — and
    /// that is the one compromise in here. At the card's own pitch "STOPPED 1"
    /// is 110 points of menu bar, and a note further down this file already
    /// measured that and called it wider than the clock, the Wi-Fi and the
    /// battery together. The lamps stay the size that makes a filled row read
    /// as a bar; the letters go small enough to be affordable.
    nonisolated static func words(_ text: String) -> NSImage {
        let bits = Self.tightened(DotMatrixText.bitmap(for: text))
        let columns = bits.first?.count ?? 0
        let size = NSSize(
            width: max(1, CGFloat(columns) * textPitch - textGap),
            height: CGFloat(DotMatrixText.height) * textPitch - textGap
        )
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor(white: 0, alpha: lit).setFill()
            for (row, line) in bits.enumerated() {
                for (column, on) in line.enumerated() where on {
                    let box = NSRect(
                        x: CGFloat(column) * textPitch,
                        // The bitmap's first row is the top; this context's
                        // origin is the bottom left.
                        y: size.height - CGFloat(row) * textPitch - textCell,
                        width: textCell, height: textCell
                    )
                    NSBezierPath(roundedRect: box,
                                 xRadius: textCell * 0.18,
                                 yRadius: textCell * 0.18).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The card and its words, as one picture.
    ///
    /// One image rather than an image and a `title`, because the title was the
    /// only thing in the item still set in the system font — a picture in the
    /// app's alphabet with a label in San Francisco beside it is two hands
    /// writing one line. Composed here so the turn can redraw the plate eight
    /// times a second without the words flickering with it.
    static func plate(_ card: ActivityCard, words text: String, turn frameIndex: Int? = nil) -> NSImage {
        let mark = glyph(card, turn: frameIndex)
        let label = words(text)
        let size = NSSize(
            width: mark.size.width + wordGap + label.size.width,
            height: max(mark.size.height, label.size.height)
        )
        let image = NSImage(size: size, flipped: false) { _ in
            mark.draw(at: NSPoint(x: 0, y: (size.height - mark.size.height) / 2),
                      from: .zero, operation: .sourceOver, fraction: 1)
            // Rounded, because a half-point offset on a 1.4pt lamp is the
            // difference between a letter and a smudge.
            let y = ((size.height - label.size.height) / 2).rounded()
            label.draw(at: NSPoint(x: mark.size.width + wordGap, y: y),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ocarina"
        return image
    }

    /// A word space, cut down to size.
    ///
    /// The alphabet draws a space as five blank columns, because on the board
    /// every glyph is five wide and the grid is the point. With the gap on
    /// either side that is seven blank columns between words — ten points of
    /// nothing, and "NEEDS YOU" read as two separate menu bar items.
    ///
    /// Cut to four. Two was the first try and it went straight past the answer:
    /// "NEEDSYOU". Four is a word space; one is the gap between letters, and it
    /// survives untouched because a run of one is under the limit.
    ///
    /// It can never eat part of a letter. A blank column *inside* a glyph has
    /// lit cells above or below it in the same column, so it is not blank.
    private nonisolated static func tightened(_ bits: [[Bool]]) -> [[Bool]] {
        guard let width = bits.first?.count, width > 0 else { return bits }
        var keep: [Int] = []
        var blankRun = 0
        for column in 0..<width {
            let empty = !bits.contains { $0[column] }
            blankRun = empty ? blankRun + 1 : 0
            if !empty || blankRun <= 4 { keep.append(column) }
        }
        return bits.map { row in keep.map { row[$0] } }
    }

    /// 1.3 rather than the card's 1.7, and the last tenth of that was bought
    /// by an exit code. `STOPPED 127` is the widest reading the bar can be
    /// asked for — 127 is "command not found" and turns up constantly — and at
    /// 1.4 it came to 126pt, close enough to the 136 a note further down this
    /// file already measured and rejected. The letters lose a tenth of a point
    /// and the worst case comes in under 120.
    private nonisolated static let textCell: CGFloat = 1.3
    private nonisolated static let textGap: CGFloat = 0.3
    private nonisolated static var textPitch: CGFloat { textCell + textGap }
    /// The space between the card and its words. Wider than a letter gap, so
    /// the two read as a plate and a caption rather than one long word.
    private nonisolated static let wordGap: CGFloat = 6

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
        item?.button?.image = Self.plate(
            .working, words: lastWords.isEmpty ? "WORKING" : lastWords, turn: frame
        )
        frame = (frame + 1) % ActivityCard.turn.count
    }

    private func stopTurning() {
        spinner?.invalidate()
        spinner = nil
    }

    private func make() -> NSStatusItem {
        // Variable, because the words are not all the same length. It was
        // `.squareLength` while the item was a picture on its own, which kept
        // it from resizing when a run ended — the cost of the words is that
        // things to its left in the menu bar now shift a few points when the
        // state changes, which is what every variable-width item up there
        // already does.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The card first, the word after it. The reading is the picture; the
        // word is what tells you which picture you are looking at.
        item.button?.imagePosition = .imageLeading
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
