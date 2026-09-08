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
/// The strip says the house line and names the app; the theme's own wording
/// is in the menu underneath. See `title(for:)` for why they are not the same
/// sentence. What either one *means* is fixed by the state it came from, so a
/// theme can be as arch as it likes about a failure in the menu without being
/// able to make one read as a success.
@MainActor
public final class ActivityStatusItem: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var spinner: Timer?
    /// The last thing we were told, kept because the menu is built from it on
    /// the way open rather than rebuilt every time the reading is refreshed.
    private var reading: Reading?
    /// Which frame of the spinner is showing. Only moves while something is
    /// running; the other three states are still pictures.
    private var frame = 0

    /// Thirty frames a second, and the head moves a third of a lamp in each
    /// of them — so a dot lights every 72ms, which is the rate the mark in the
    /// sidebar and the marks on the website all run at. One clock for the
    /// chase wherever it appears.
    private static let framerate: TimeInterval = 1.0 / 30
    private static let step: Double = (1.0 / 30) / 0.072

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
            stopSpinning()
            return
        }

        let item = self.item ?? make()
        self.item = item

        // Nothing said anything new. Returning here is not only a saving: the
        // spinner is a timer that this would otherwise tear down and rebuild
        // on every fifteen-second usage refresh, which is a visible stutter in
        // something whose whole job is to turn smoothly.
        let wasSaying = self.reading.map { Self.title(for: $0.activity ?? .idle) }
        self.reading = reading

        let line = Self.title(for: activity)
        item.button?.toolTip = Self.tooltip(for: activity, reading: reading)
        guard line != wasSaying else { return }

        // The spinner owns the board while something is running, so drawing it
        // here as well would fight the timer for the same image.
        if activity.isRunning {
            startSpinning(saying: line)
        } else {
            stopSpinning()
            item.button?.image = Self.board(line, head: nil)
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

    /// What the strip beside the Wi-Fi actually says.
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
    /// The app's name is no longer in front of them. It was there because a
    /// strip of text beside the Wi-Fi has nothing to say whose it is — but
    /// the strip is not text any more, it is Ocarina's own alphabet, and a
    /// dot-matrix board saying "still going" beside a row of system glyphs is
    /// already unmistakably from one place. Saying the name as well was the
    /// mark and the wordmark on the same object.
    ///
    /// - **still going** — your ask has not come back yet.
    /// - **back to you** — the agent stopped and it is your move. Not "done":
    ///   the agent stopping does not mean it managed what you asked, and the
    ///   word up here has to be one this can support.
    /// - **ready** — nothing has been asked in this tab yet.
    /// - **stopped (n)** — it exited, and here is the number.
    nonisolated static func title(for activity: TabActivity) -> String {
        switch activity {
        case .idle: "READY"
        case .running: "STILL GOING"
        case .succeeded: "BACK TO YOU"
        // Same rule as `line`: the code is appended here, not written by a
        // theme, so a failure in the menu bar always carries its number.
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
        // The code goes here rather than in the theme's line, so a theme
        // cannot write a failure that does not carry its number.
        case let .failed(code): "\(speech.stopped) (\(code))"
        }
    }

    /// The long form, for the tooltip — the sentence the line is the short
    /// version of, with the task named when there is one.
    nonisolated static func tooltip(for activity: TabActivity, reading: Reading) -> String {
        let line = line(for: activity, speech: reading.speech)
        guard let task = reading.task, !task.isEmpty else { return "Ocarina — \(line)" }
        return "Ocarina — \(line): \(task)"
    }

    // MARK: - The board

    /// The line, drawn in the app's own 5x7 alphabet.
    ///
    /// The menu bar used to be a system-font string with a braille spinner in
    /// front of it and an SF Symbol beside it — three different alphabets for
    /// one reading, none of them Ocarina's. This is one: the same grid the
    /// wordmark, the landing screen and the token meter are built from, at the
    /// size a menu bar has room for.
    ///
    /// A template image, so the menu bar tints it — which is also why the
    /// chase is expressed as *alpha* rather than as colour. A template has no
    /// colour of its own to vary; what it has is how much of the bar's own ink
    /// each dot asks for, and that turns out to be the right model for a lamp
    /// anyway.
    ///
    /// Unlit cells are drawn too, faintly. They are what make it a board
    /// rather than words made of dots, and at this size they are the only
    /// thing that says the lit ones are lit.
    static func board(_ text: String, head: Double?) -> NSImage {
        let bits = DotMatrixText.bitmap(for: text)
        let columns = max(0, text.count * 6 - 1)
        guard columns > 0 else { return NSImage(size: NSSize(width: 1, height: 1)) }

        let size = NSSize(
            width: CGFloat(columns) * pitch - gap,
            height: CGFloat(DotMatrixText.height) * pitch - gap
        )
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()

        // Ranked in the order the head travels: column by column, top to
        // bottom, the same order the mark in the sidebar sweeps in.
        var rank: [Int: Double] = [:]
        var lit = 0
        for column in 0..<columns {
            for row in 0..<DotMatrixText.height where bits[row][column] {
                rank[row * columns + column] = Double(lit)
                lit += 1
            }
        }
        let total = Double(lit) + Self.rest

        for row in 0..<DotMatrixText.height {
            for column in 0..<columns {
                let box = NSRect(
                    x: CGFloat(column) * pitch,
                    // Flipped: the bitmap's first row is the top, and this
                    // context's origin is the bottom left.
                    y: size.height - CGFloat(row) * pitch - cell,
                    width: cell,
                    height: cell
                )
                let alpha: Double
                if bits[row][column] {
                    // The head brightens; it does not dim everything else to
                    // make room. At a base of 0.62 the running board read
                    // fainter than the resting one, which is backwards — of
                    // the four states it is the one you most want to catch out
                    // of the corner of an eye.
                    alpha = 0.84 + 0.16 * drive(rank[row * columns + column] ?? 0,
                                                head: head, total: total)
                } else {
                    alpha = 0.13
                }
                NSColor(white: 0, alpha: alpha).setFill()
                NSBezierPath(roundedRect: box, xRadius: cell * 0.3, yRadius: cell * 0.3).fill()
            }
        }
        image.unlockFocus()
        // Tinted by the menu bar, so it inverts with it the way every system
        // item does rather than staying one colour through both.
        image.isTemplate = true
        return image
    }

    /// How hard one lamp is being driven, given where the head is.
    ///
    /// The sidebar's numbers, at the sidebar's proportions — see the chase on
    /// `DotMatrixText`. Nil means nothing is running, and every lamp is simply
    /// on.
    private nonisolated static func drive(_ position: Double, head: Double?, total: Double) -> Double {
        guard let head else { return 1 }
        var distance = head - position
        if distance < -lead { distance += total }
        if distance >= 0, distance < trail { return 1 - distance / trail }
        if distance < 0, distance > -lead { return 1 + distance / lead }
        return 0
    }

    /// A menu bar is about twenty-two points tall and seven rows have to sit
    /// in it with room above and below, which settles the cell and the gap.
    private nonisolated static let cell: CGFloat = 1.4
    private nonisolated static let gap: CGFloat = 0.7
    private nonisolated static var pitch: CGFloat { cell + gap }
    private nonisolated static let trail: Double = 15
    private nonisolated static let rest: Double = 26
    private nonisolated static let lead: Double = 1.4

    // MARK: - The spinner

    private func startSpinning(saying line: String) {
        spinner?.invalidate()
        // Drawn once immediately: a timer that fires in 33ms would otherwise
        // leave the previous state's board up for a frame you can see.
        frame = 0
        draw(line)
        let timer = Timer(timeInterval: Self.framerate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw(line) }
        }
        // `.common`, not the default mode: a status item stops updating while
        // a menu is open or a window is being dragged if the timer only runs
        // in the default run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        spinner = timer
    }

    /// One frame of the chase, sweeping the head along the word.
    ///
    /// The braille spinner this replaced was a good answer to a different
    /// question — every tool in a terminal turns one, so it needed no
    /// explaining — but it sat in front of a system-font string and made the
    /// reading three alphabets wide. The board says the same thing by lighting
    /// its own lamps, which is what a board does and what the rest of the app
    /// already does everywhere else.
    private func draw(_ line: String) {
        frame += 1
        item?.button?.image = Self.board(line, head: Double(frame) * Self.step)
    }

    private func stopSpinning() {
        spinner?.invalidate()
        spinner = nil
    }

    private func make() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        // Monospaced digits so the exit code in a failure line does not shift
        // the item's width as it changes, and — more to the point — so the
        // braille frames all measure the same and the spinner turns on the
        // spot rather than nudging everything to its right ten times a second.
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
