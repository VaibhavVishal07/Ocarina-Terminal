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
            item("Quick Actions…", #selector(toggleQuickActions), "k")
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

        menu.addItem(submenu(named: "View", items: [
            item("Command Palette…", #selector(toggleCommandPalette), "p",
                 modifiers: [.command, .shift]),
            .separator(),
            item("Tasks", #selector(toggleTaskPanel), "j"),
            .separator(),
            item("Theme\u{2026}", #selector(showThemePicker)),
            .separator(),
            item("Keep This Mac Awake", #selector(toggleSleepGuard))
        ]))
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


    @objc private func toggleTaskPanel() {
        model.setTaskPanel(visible: !model.isTaskPanelVisible)
    }

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
        case #selector(closeTab):
            return model.selectedTabID != nil
        case #selector(toggleSleepGuard):
            menuItem.state = model.sleepGuard.isHolding ? .on : .off
            return true
        default:
            return true
        }
    }
}
