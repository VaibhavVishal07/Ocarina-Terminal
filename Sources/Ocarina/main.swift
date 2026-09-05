import AppKit
import OcarinaUI
import SwiftUI

/// Ocarina runs as a plain SwiftPM executable, so it asks AppKit for a normal
/// windowed app rather than inheriting the accessory behaviour of a CLI.
@MainActor
private func run() {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)

    let controller = NSHostingController(rootView: OcarinaWindowView())
    let window = NSWindow(contentViewController: controller)
    window.title = "Ocarina"
    window.setContentSize(NSSize(width: 980, height: 620))
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.center()
    window.makeKeyAndOrderFront(nil)

    application.activate(ignoringOtherApps: true)
    application.run()
}

run()
