import AppKit
import SwiftUI

/// An AppKit tool tip attached to a SwiftUI control.
///
/// SwiftUI's `.help` produces nothing in a plain `NSHostingController` — the
/// view tree comes back with no tool tip on it at all. AppKit's own tool tip
/// always works, but it has to live on a real `NSView` that the tool tip
/// manager can find under the cursor, which means that view sits over the
/// control and takes the mouse. So it passes the click on instead.
private struct ToolTipOverlay: NSViewRepresentable {
    let text: String
    let onClick: () -> Void

    final class HotView: NSView {
        var onClick: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            onClick()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    func makeNSView(context: Context) -> HotView {
        let view = HotView()
        view.toolTip = text
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: HotView, context: Context) {
        view.toolTip = text
        view.onClick = onClick
    }
}

extension View {
    /// Explains the control on hover, and handles its click.
    func toolTip(_ text: String, onClick: @escaping () -> Void) -> some View {
        overlay(ToolTipOverlay(text: text, onClick: onClick))
    }
}
