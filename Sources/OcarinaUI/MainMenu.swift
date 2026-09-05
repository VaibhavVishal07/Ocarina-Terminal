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
        menu.addItem(submenu(named: "Ocarina", items: [
            item("About Ocarina", #selector(showAbout)),
            .separator(),
            chainItem("Hide Ocarina", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            chainItem("Quit Ocarina", #selector(NSApplication.terminate(_:)), "q")
        ]))

        menu.addItem(submenu(named: "File", items: [
            item("New Tab", #selector(newTab), "t"),
            item("Close Tab", #selector(closeTab), "w")
        ]))

        // A terminal without ⌘C / ⌘V is not a terminal. These go to whatever
        // holds first responder — SwiftTerm implements them.
        menu.addItem(submenu(named: "Edit", items: [
            chainItem("Cut", #selector(NSText.cut(_:)), "x"),
            chainItem("Copy", #selector(NSText.copy(_:)), "c"),
            chainItem("Paste", #selector(NSText.paste(_:)), "v"),
            chainItem("Select All", #selector(NSText.selectAll(_:)), "a")
        ]))

        menu.addItem(submenu(named: "View", items: [
            item("Command Palette…", #selector(toggleCommandPalette), "p",
                 modifiers: [.command, .shift]),
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

    @objc private func toggleSleepGuard() { model.sleepGuard.isEnabled.toggle() }

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
