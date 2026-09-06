import AppKit
import OcarinaTerminalContext

/// The same reading as the card, up in the menu bar beside the Wi-Fi.
///
/// It exists because the card is only useful while you are looking at Ocarina,
/// and the question it answers — how long have I got — is one you have while
/// you are looking at something else.
///
/// It appears and disappears with the card, for the same reason: a permanent
/// menu bar item that says nothing most of the day is furniture, and the menu
/// bar is the most expensive strip of screen on the Mac to leave furniture in.
@MainActor
public final class UsageStatusItem {
    private var item: NSStatusItem?
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public init() {}

    /// Nil takes the item out of the menu bar entirely rather than blanking it.
    public func update(with usage: UsageWindow?, now: Date = Date()) {
        guard let usage else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }

        let item = self.item ?? make()
        self.item = item
        item.button?.title = " \(UsageCardView.compact(usage.tokens)) · \(Self.countdown(to: usage.resetsAt, from: now))"
        item.button?.toolTip = """
        Ocarina — tokens used in the window that opened at \
        \(Self.clock.string(from: usage.startedAt)).
        """
        item.menu = menu(for: usage, now: now)
    }

    private func make() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A template image, so it inverts with the menu bar the way every
        // system item does rather than staying one colour through both.
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "Token usage"
        )
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        return item
    }

    /// Read-only, and it says the thing the number cannot say for itself.
    private func menu(for usage: UsageWindow, now: Date) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.line("\(usage.tokens.formatted()) tokens used"))
        menu.addItem(Self.line("Window opened \(Self.clock.string(from: usage.startedAt))"))
        menu.addItem(Self.line("Resets \(Self.clock.string(from: usage.resetsAt))"))
        menu.addItem(.separator())
        // Said out loud rather than left for someone to assume. A meter that
        // looks like it knows the allowance, and does not, is worse than one
        // that admits it.
        menu.addItem(Self.line("Tokens remaining are not shown: nothing on"))
        menu.addItem(Self.line("this Mac records the size of the allowance."))
        return menu
    }

    private static func line(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
