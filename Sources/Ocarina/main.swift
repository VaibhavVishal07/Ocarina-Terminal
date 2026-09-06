import AppKit
import OcarinaUI
import SwiftUI

/// Ocarina runs as a plain SwiftPM executable, so it asks AppKit for a normal
/// windowed app rather than inheriting the accessory behaviour of a CLI.
@MainActor
private func run() {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    // Before any view is built, or the first frame draws in the fallback face.
    BundledFonts.register()
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
    // Just the product name. The full bundle name — "Ocarina Test Build" —
    // was long enough to straddle the sidebar's edge, half on the panel and
    // half on the terminal; one short word sits inside the panel and stays on
    // one surface. Which build this is still shows in the menu bar, the Dock
    // and ⌘-Tab, all of which read the bundle rather than this.
    window.title = AppIdentity.product
    // The sidebar carries the wordmark in the board's dot matrix now, and the
    // titlebar's text sits about ten points above it. One of them had to go, and
    // the drawn one is the one that is ours. The title itself stays set, so the
    // Window menu and the accessibility tree still name the window.
    window.titleVisibility = .hidden
    window.setContentSize(NSSize(width: 980, height: 620))
    // Without this the window shrinks past what the content can lay out, and
    // AppKit simply clips the overflow: the sidebar slides off the left edge,
    // taking the first characters of every tab name with it.
    window.contentMinSize = NSSize(width: OcarinaWindowView.minimumSize.width,
                                   height: OcarinaWindowView.minimumSize.height)
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
