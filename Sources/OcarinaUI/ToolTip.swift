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
    /// Nil for a control that handles its own clicks. The catcher is an
    /// `NSView` that overrides `mouseDown`, so laying it over something already
    /// interactive — a real `Toggle`, say — explains the control and then
    /// swallows every attempt to use it.
    let onClick: (() -> Void)?

    @State private var isHovering = false
    @State private var frame: CGRect = .zero
    /// The text this control actually put on screen, so it clears its own tip
    /// and only its own. Comparing against `text` was not enough: a tip whose
    /// wording depends on state — the keep-awake line changes with it — would
    /// go to hide, find the current wording no longer matching what it showed,
    /// and leave the bubble up for good.
    @State private var shown: String?
    @State private var showTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    /// Long enough that crossing the control on the way somewhere else never
    /// summons it.
    private static let appearAfter = Duration.seconds(2)
    /// Short, but not instant: the bubble should not vanish out from under a
    /// pointer that clipped the edge of the control on its way past.
    private static let disappearAfter = Duration.milliseconds(500)

    @ViewBuilder
    func body(content: Content) -> some View {
        let measured = content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { frame = geometry.frame(in: .named(space)) }
                        .onChange(of: geometry.frame(in: .named(space))) { _, new in
                            frame = new
                        }
                }
            }

        let wired: AnyView = if let onClick {
            AnyView(measured.overlay { HoverCatcher(onClick: onClick, onHover: hover) })
        } else {
            AnyView(measured.onHover(perform: hover))
        }

        wired.onDisappear(perform: dismiss)
    }

    /// Takes the bubble down when the control it explains is removed.
    ///
    /// This is the "Close this tab (⌘W)" tip that would not go away. The close
    /// button only exists while its row is hovered, and a view taken out of
    /// the tree never gets `mouseExited` — so leaving the row quickly enough
    /// deleted the control while its tip was up, and nothing was left to
    /// retract it. It sat there until some other control replaced it.
    ///
    /// Every control that can disappear under the pointer has the same
    /// problem, which is why this is here rather than in the tab row.
    private func dismiss() {
        showTask?.cancel()
        hideTask?.cancel()
        isHovering = false
        if let shown, target?.text == shown { target = nil }
        shown = nil
    }

    private func hover(_ hovering: Bool) {
        isHovering = hovering
        // Both directions are cancellable, and each cancels the other. A
        // pointer that leaves during the wait must not have a tip appear
        // behind it, and one that comes back during the fade must not have it
        // taken away.
        showTask?.cancel()
        hideTask?.cancel()

        if hovering {
            showTask = Task { @MainActor in
                try? await Task.sleep(for: Self.appearAfter)
                guard !Task.isCancelled, isHovering else { return }
                shown = text
                withAnimation(.easeOut(duration: 0.12)) {
                    target = ToolTipTarget(text: text, anchor: frame)
                }
            }
        } else {
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: Self.disappearAfter)
                guard !Task.isCancelled, !isHovering else { return }
                if let shown, target?.text == shown {
                    withAnimation(.easeOut(duration: 0.12)) { target = nil }
                }
                shown = nil
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

    /// Explains the control on hover and leaves its clicks alone.
    func toolTip(
        _ text: String,
        in space: String,
        target: Binding<ToolTipTarget?>
    ) -> some View {
        modifier(ToolTipModifier(text: text, space: space, target: target, onClick: nil))
    }
}

/// The bubble itself. Drawn by whoever owns the coordinate space, so it is not
/// clipped by anything the control happens to sit inside.
struct ToolTipBubble: View {
    @Environment(\.theme) private var theme
    let target: ToolTipTarget
    /// Width available to place the bubble in, for keeping it on screen.
    let width: CGFloat
    /// Height available, for the same reason vertically.
    let height: CGFloat

    /// Measured rather than assumed: where the bubble goes depends on how tall
    /// it turned out to be.
    @State private var bubbleHeight: CGFloat = 0

    private static let maxWidth: CGFloat = 250
    private static let margin: CGFloat = 6
    private static let font = NSFont.systemFont(ofSize: 11)

    /// The bubble's width, measured rather than negotiated.
    ///
    /// The obvious spelling — `frame(maxWidth:)` plus `fixedSize()` — does not
    /// work here, and produced the bubble whose padding ran out on the right.
    /// A max-width frame given no proposal reports the capped width without
    /// re-proposing it to the text inside, so the chrome settled at one width
    /// and the text laid itself out at another. Dropping `fixedSize` instead
    /// hands the bubble the sidebar's own 165 and every tip wraps to a column.
    ///
    /// Measuring the string is the way out: an explicit width ignores whatever
    /// the sidebar proposes, so a short tip still hugs its text and a long one
    /// wraps at the cap, and the chrome is wrapped around a width that is
    /// already decided.
    private var textWidth: CGFloat {
        let ideal = (target.text as NSString)
            .size(withAttributes: [.font: Self.font])
            .width
        return min(ceil(ideal), Self.maxWidth)
    }

    var body: some View {
        Text(target.text)
            .font(.system(size: 11))
            .foregroundStyle(theme.chrome.textPrimary.color)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: textWidth, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    // Solid, not material: a blur here picks up whatever
                    // terminal text sits behind the bubble, and on a light
                    // theme it picks up the desktop instead.
                    .fill(theme.chrome.panelTop.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.chrome.border.color.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { bubbleHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, new in bubbleHeight = new }
                }
            }
            .offset(x: x, y: y)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    /// Left-aligned to the control, then pulled back so a control near the
    /// right edge does not push its tip off the window.
    private var x: CGFloat {
        let room = Self.maxWidth + 24
        return min(max(8, target.anchor.minX), max(8, width - room))
    }

    /// Below the control, or above it when there is no room below.
    ///
    /// Everything with a tip on it used to live in the scrolling list near the
    /// top, so below was always right. The keep-awake row sits on the floor of
    /// the panel, and its tip was being drawn past the bottom edge of the
    /// window — placed correctly, and invisible.
    private var y: CGFloat {
        let below = target.anchor.maxY + Self.margin
        guard below + bubbleHeight > height else { return below }
        return max(Self.margin, target.anchor.minY - bubbleHeight - Self.margin)
    }
}
