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

    /// The spinner, in braille. A terminal app has one alphabet for "this is
    /// going" that every tool in the terminal already uses, and it is this
    /// one — so the menu bar borrows it rather than inventing a third mark
    /// after the tab's dot and the app's own ring.
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    /// Ten frames at this interval is one turn a second, which reads as
    /// working rather than as urgent.
    private static let framerate: TimeInterval = 0.1

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
        item.button?.image = Self.symbol(for: activity)
        item.button?.toolTip = Self.tooltip(for: activity, reading: reading)
        guard line != wasSaying else { return }

        // The spinner owns the title while something is running, so setting it
        // here as well would fight the timer for the same string.
        if activity.isRunning {
            startSpinning(saying: line)
        } else {
            stopSpinning()
            item.button?.title = " \(line)"
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
    /// So the strip names the app and the state, in the same four words every
    /// theme gets. The register is not lost — it is one click down, in
    /// `menuNeedsUpdate`, where you have already pressed something belonging
    /// to Ocarina and know whose voice you are reading.
    nonisolated static func title(for activity: TabActivity) -> String {
        switch activity {
        case .idle: "Ocarina Idle"
        case .running: "Ocarina Working"
        case .succeeded: "Ocarina Done"
        // Same rule as `line`: the code is appended here, not written by a
        // theme, so a failure in the menu bar always carries its number.
        case let .failed(code): "Ocarina Stopped (\(code))"
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

    private static func symbol(for activity: TabActivity) -> NSImage? {
        // No image at all while it runs: the braille frame in the title is the
        // mark, and a static symbol beside a moving one reads as two things
        // happening.
        let name: String? = switch activity {
        case .running: nil
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .idle: "circle.dotted"
        }
        guard let name else { return nil }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        // A template image, so it inverts with the menu bar the way every
        // system item does rather than staying one colour through both.
        image?.isTemplate = true
        return image
    }

    // MARK: - The spinner

    private func startSpinning(saying line: String) {
        spinner?.invalidate()
        // Drawn once immediately: a timer that fires in 100ms would otherwise
        // leave the previous state's title up for a frame you can see.
        draw(line)
        let timer = Timer(timeInterval: Self.framerate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw(line) }
        }
        // `.common`, not the default mode: a status item's title stops
        // updating while a menu is open or a window is being dragged if the
        // timer only runs in the default run loop mode.
        RunLoop.main.add(timer, forMode: .common)
        spinner = timer
    }

    private func draw(_ line: String) {
        frame = (frame + 1) % Self.frames.count
        item?.button?.title = " \(Self.frames[frame]) \(line)"
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
