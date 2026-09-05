import AppKit
import OcarinaUI
import SwiftUI

/// Ocarina runs as a plain SwiftPM executable, so it asks AppKit for a normal
/// windowed app rather than inheriting the accessory behaviour of a CLI.
@MainActor
private func run() {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    // A bare SwiftPM executable has no bundle to read an icon from, so the dock
    // is told directly.
    application.applicationIconImage = OcarinaIcon.app

    // The model is made here so the menu bar and the window act on the same one.
    let model = OcarinaModel()
    let menuController = MainMenuController(model: model)
    application.mainMenu = menuController.menu

    let hosting = NSHostingView(rootView: OcarinaWindowView(model: model))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    // Glass needs something behind it to blur. Without this the materials in
    // the chrome have only the window's own background to work with and come
    // out as flat grey.
    let backdrop = NSVisualEffectView()
    backdrop.material = .underWindowBackground
    backdrop.blendingMode = .behindWindow
    backdrop.state = .active
    backdrop.autoresizingMask = [.width, .height]

    let container = NSView(frame: window.contentLayoutRect)
    backdrop.frame = container.bounds
    hosting.frame = container.bounds
    hosting.autoresizingMask = [.width, .height]
    container.addSubview(backdrop)
    container.addSubview(hosting)
    window.contentView = container
    window.isOpaque = false
    window.backgroundColor = .clear
    window.title = "Ocarina"
    window.setContentSize(NSSize(width: 980, height: 620))
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.center()
    window.makeKeyAndOrderFront(nil)

    application.activate(ignoringOtherApps: true)
    // menuController is referenced past this point only through the menu, whose
    // items hold their target weakly, so keep it alive for the app's lifetime.
    withExtendedLifetime(menuController) {
        application.run()
    }
}

run()
