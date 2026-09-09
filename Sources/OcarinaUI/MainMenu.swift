import AppKit

/// The app's menu bar.
///
/// Ocarina had no main menu at all, which is why ⌘W did nothing. AppKit offers
/// a key equivalent to the main menu *before* it reaches the window or the
/// responder chain, so with no menu there was nothing to offer it to — and ⌘Q
/// had no home either. Hidden SwiftUI buttons carrying `.keyboardShortcut` are
/// not a substitute: they only ever see an event that gets as far as the view
/// hierarchy, which a terminal view holding first responder can swallow.
@MainActor
public final class MainMenuController: NSObject {
    public let menu = NSMenu()
    private let model: OcarinaModel

    public init(model: OcarinaModel) {
        self.model = model
        super.init()
        build()
    }

    private func build() {
        // Named from the bundle, so a test build says so in the one menu
        // that is always on screen.
        let app = AppIdentity.name
        menu.addItem(submenu(named: app, items: [
            item("About \(app)", #selector(showAbout)),
            .separator(),
            // It was a row in the sidebar, under Theme, on the reasoning that
            // the people this app is for are the ones least likely to go
            // looking for where to complain. That reasoning still holds and
            // this is still a visible place: the app menu is the first menu in
            // the bar, it is there before a tab is open, and it is where every
            // Mac app has kept this for twenty years — so it is the one place
            // somebody looks *without* being taught.
            //
            // What the move buys is the sidebar's lower card, which was five
            // rows of two different kinds. Four rows split cleanly into a card
            // of switches and a card of doors; five did not.
            item("Share Feedback\u{2026}", #selector(showFeedback)),
            .separator(),
            chainItem("Hide \(app)", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            chainItem("Quit \(app)", #selector(NSApplication.terminate(_:)), "q")
        ]))

        menu.addItem(submenu(named: "File", items: [
            item("New Tab", #selector(newTab), "t"),
            item("Close Tab", #selector(closeTab), "w"),
            .separator(),
            // ⇧⌘K, because ⌘K belongs to Clear.
            //
            // Every Mac terminal since Terminal.app has cleared on ⌘K, and a
            // person arriving here presses it expecting an empty window. It
            // opened a drawer of agent installers instead — which is the exact
            // failure of inventing a shortcut where a convention already
            // exists. Quick Actions loses nothing by moving: it is a thing you
            // reach for once a machine, and it is still on the landing screen.
            item("Quick Actions…", #selector(toggleQuickActions), "k",
                 modifiers: [.command, .shift])
        ]))

        // A terminal without ⌘C / ⌘V is not a terminal. These go to whatever
        // holds first responder — SwiftTerm implements them.
        menu.addItem(submenu(named: "Edit", items: [
            chainItem("Cut", #selector(NSText.cut(_:)), "x"),
            chainItem("Copy", #selector(NSText.copy(_:)), "c"),
            // Targeted, not chained: the point is to look at the text before
            // SwiftTerm ever sees it.
            item("Paste", #selector(pasteWithReview), "v"),
            chainItem("Select All", #selector(NSText.selectAll(_:)), "a")
        ]))

        // Moving between sessions lives here rather than in a Window menu of
        // its own. Terminal.app and Safari keep tab navigation under Window —
        // but they also keep Minimize and Zoom there, and a Window menu
        // holding nothing but "Next Session" is more surprising than no Window
        // menu at all.
        menu.addItem(submenu(named: "View", items: [
            item("Command Palette…", #selector(toggleCommandPalette), "p",
                 modifiers: [.command, .shift]),
            .separator(),
            // ⇧⌘] and ⇧⌘[ — what Terminal.app, Safari and Chrome all use to
            // walk a row of tabs. They step through the column's own order,
            // not the order sessions were last used: a shortcut that moved you
            // through an order with no representation on screen is one you
            // cannot predict. See `OcarinaModel.selectNextTab`.
            item("Next Session", #selector(nextSession), "]",
                 modifiers: [.command, .shift]),
            item("Previous Session", #selector(previousSession), "[",
                 modifiers: [.command, .shift]),
            // Nine of them, in a submenu rather than nine rows in View. The
            // key equivalents work the same either way, and this is a list
            // nobody opens — it is here so ⌘4 has somewhere to be registered.
            goToSubmenu(),
            .separator(),
            item("Clear Terminal", #selector(clearTerminal), "k"),
            .separator(),
            item("Theme\u{2026}", #selector(showThemePicker)),
            .separator(),
            item("Keep This Mac Awake", #selector(toggleSleepGuard))
        ]))
    }

    /// ⌘1 through ⌘9, by position in the column.
    ///
    /// Counting from one, and ⌘9 is the ninth rather than the last. Browsers
    /// make ⌘9 mean "the last one"; terminals do not, and this is a terminal —
    /// somebody who has learned that ⌘3 is the third tab should not find that
    /// the rule stops holding at nine.
    private func goToSubmenu() -> NSMenuItem {
        let holder = NSMenuItem(title: "Go to Session", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Go to Session")
        for position in 1...9 {
            let row = item("Session \(position)", #selector(goToSession(_:)), "\(position)")
            row.tag = position
            sub.addItem(row)
        }
        holder.submenu = sub
        return holder
    }

    private func submenu(named title: String, items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        holder.submenu = submenu
        return holder
    }

    /// An item this controller handles itself.
    private func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let menuItem = chainItem(title, action, key, modifiers: modifiers)
        menuItem.target = self
        return menuItem
    }

    /// An item with no target, so the action travels the responder chain to
    /// whatever holds first responder. The system commands and the editing
    /// commands both want this — SwiftTerm implements cut/copy/paste itself.
    private func chainItem(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }

    // MARK: - Actions

    @objc private func newTab() { model.newTab() }


    @objc private func closeTab() {
        guard let id = model.selectedTabID else { return }
        model.closeTab(id)
    }

    @objc private func toggleCommandPalette() { model.isCommandPaletteVisible.toggle() }

    @objc private func toggleQuickActions() { model.isQuickActionsVisible.toggle() }


    @objc private func nextSession() { model.selectNextTab() }

    @objc private func previousSession() { model.selectPreviousTab() }

    @objc private func goToSession(_ sender: NSMenuItem) {
        model.selectTab(at: sender.tag)
    }

    @objc private func clearTerminal() { model.clearSelectedTerminal() }

    @objc private func showThemePicker() { model.isThemePickerVisible = true }

    @objc private func pasteWithReview() {
        // While a tab is being renamed the focused thing is a text field, and
        // the paste belongs to *it*. Routing everything to the terminal meant
        // ⌘V during a rename typed into the shell behind the field — the text
        // went somewhere the user was not looking. `TerminalView` is an
        // `NSView`, not an `NSTextView`, so this tells the two apart.
        if let window = NSApp.keyWindow, window.firstResponder is NSTextView {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        model.requestPaste(NSPasteboard.general.string(forType: .string))
    }

    @objc private func toggleSleepGuard() { model.sleepGuard.isEnabled.toggle() }

    @objc private func showFeedback() { model.isFeedbackVisible = true }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
}

extension MainMenuController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closeTab), #selector(clearTerminal):
            return model.selectedTabID != nil
        // Greyed rather than absent. The pair only means anything with
        // somewhere to go, and a live "Next Session" in a window holding one
        // session is a shortcut that answers by doing nothing.
        case #selector(nextSession), #selector(previousSession):
            return model.tabs.count > 1
        case #selector(goToSession(_:)):
            return menuItem.tag <= model.tabs.count
        case #selector(toggleSleepGuard):
            menuItem.state = model.sleepGuard.isHolding ? .on : .off
            return true
        default:
            return true
        }
    }
}
