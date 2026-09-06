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
    // Repainted from the theme as soon as the view appears; this is only what
    // the window wears for the frame before that.
    window.backgroundColor = .black
    // The bar keeps its place in the layout — the content still starts below
    // it — but takes the window's colour rather than the system's, so it is
    // the same surface as the ground the panels float on. The hairline under
    // it is asked for by name in `tintWindows`, because transparency drops it.
    window.titlebarAppearsTransparent = true
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
    // A real titlebar, with nothing written in it.
    //
    // It was `.fullSizeContentView` over a transparent titlebar, which is the
    // arrangement that hides the bar entirely and lets the content run up
    // under the traffic lights. Every edge in the window then had to clear a
    // bar that was not drawn — the sidebar with a spacer, the terminal with an
    // inset, the error banner with 30pt of padding — and the top of the window
    // was one unbroken surface with three lights floating on it.
    //
    // The bar is back and it earns its place twice: it is somewhere to hold
    // the window that is not the text you are reading, and the hairline under
    // it is the line the panels below now sit clear of. Nothing is written
    // there; `titleVisibility` keeps the name for the Window menu and the
    // accessibility tree without drawing it.
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
