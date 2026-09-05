import AppKit
import SwiftUI

/// Where a tool tip should be drawn, and what it says.
struct ToolTipTarget: Equatable {
    let text: String
    /// The control's frame, in the tab strip's coordinate space.
    let anchor: CGRect
}

/// Reports hover and takes the click for one control.
///
/// Three mechanisms were tried before this. SwiftUI's `.help` produces nothing
/// in a plain `NSHostingController` — the view tree comes back with no tool tip
/// on it at all. AppKit's `NSView.toolTip` does get installed on a view that is
/// hit-testable at the right frame, but never appears: the tool tip manager
/// needs mouse-moved events to reach the view under the cursor, and inside a
/// hosting view they do not arrive. A SwiftUI bubble drawn by the control
/// itself is clipped away by the scroll view the tabs live in.
///
/// So the control only *reports*: the strip draws the bubble, outside the
/// scroller. The small `NSView` stays because it is also what makes the click
/// reliable where SwiftUI gestures compete for it.
private struct HoverCatcher: NSViewRepresentable {
    let onClick: () -> Void
    let onHover: (Bool) -> Void

    final class CatchingView: NSView {
        var onClick: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }
        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }

    func makeNSView(context: Context) -> CatchingView {
        let view = CatchingView()
        view.onClick = onClick
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: CatchingView, context: Context) {
        view.onClick = onClick
        view.onHover = onHover
    }
}

private struct ToolTipModifier: ViewModifier {
    let text: String
    let space: String
    @Binding var target: ToolTipTarget?
    let onClick: () -> Void

    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { frame = geometry.frame(in: .named(space)) }
                        .onChange(of: geometry.frame(in: .named(space))) { _, new in
                            frame = new
                        }
                }
            }
            .overlay { HoverCatcher(onClick: onClick, onHover: hover) }
    }

    private func hover(_ hovering: Bool) {
        isHovering = hovering
        guard hovering else {
            if target?.text == text { target = nil }
            return
        }
        Task { @MainActor in
            // The usual beat before a tip appears, so sweeping the pointer
            // across a row of controls does not flash one at each.
            try? await Task.sleep(for: .milliseconds(400))
            guard isHovering else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                target = ToolTipTarget(text: text, anchor: frame)
            }
        }
    }
}

extension View {
    /// Explains the control on hover — through `target`, which the strip draws
    /// — and handles its click.
    func toolTip(
        _ text: String,
        in space: String,
        target: Binding<ToolTipTarget?>,
        onClick: @escaping () -> Void
    ) -> some View {
        modifier(ToolTipModifier(text: text, space: space, target: target, onClick: onClick))
    }
}

/// The bubble itself. Drawn by whoever owns the coordinate space, so it is not
/// clipped by anything the control happens to sit inside.
struct ToolTipBubble: View {
    let target: ToolTipTarget
    /// Width available to place the bubble in, for keeping it on screen.
    let width: CGFloat

    private static let maxWidth: CGFloat = 250

    var body: some View {
        Text(target.text)
            .font(.system(size: 11))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            }
            .fixedSize()
            .offset(x: x, y: target.anchor.maxY + 6)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    /// Left-aligned to the control, then pulled back so a control near the
    /// right edge does not push its tip off the window.
    private var x: CGFloat {
        let room = Self.maxWidth + 24
        return min(max(8, target.anchor.minX), max(8, width - room))
    }
}
