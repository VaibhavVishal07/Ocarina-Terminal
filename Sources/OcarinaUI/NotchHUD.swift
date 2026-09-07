import AppKit
import Observation
import SwiftUI

/// What the drop is currently saying.
///
/// A holder the panel's root view observes, rather than a new root view per
/// change. Swapping an `NSHostingView`'s `rootView` replaces the tree, and a
/// replaced tree has no former self to animate from — the drop would appear at
/// its destination instead of coming out. Mutating one property on an observed
/// object inside `withAnimation` is the same change with something to animate.
@MainActor
@Observable
final class NotchState {
    var title = ""
    /// How far out, 0 to 1.
    var progress: Double = 0
    var theme: Theme = .fallback
}

private struct NotchRoot: View {
    let state: NotchState
    let onPress: () -> Void

    var body: some View {
        NotchDrop(title: state.title, progress: state.progress)
            .environment(\.theme, state.theme)
            .onTapGesture(perform: onPress)
    }
}

/// The window the drop lives in, and the thing that decides when to show it.
///
/// A panel rather than a window, borderless and non-activating: it appears over
/// whatever you are doing, and it must not steal focus from the app you are
/// actually in unless you press the drop itself.
@MainActor
public final class NotchHUD {
    /// How long it stays out before going back.
    ///
    /// Long enough to read six words and look up, short enough that it is gone
    /// before it is in the way. It does not wait to be dismissed: there is no
    /// close button on it, because a thing you have to put away is a thing that
    /// costs you something every time it appears.
    public static let dwell: TimeInterval = 3.4
    private static let slide: TimeInterval = 0.32

    private var panel: NSPanel?
    private let state = NotchState()
    private var hideTask: Task<Void, Never>?
    /// Which drop is on screen. Every timer checks this before acting, so a
    /// task that finishes during a retraction takes the panel over cleanly
    /// rather than being ordered out by the timer it interrupted.
    private var generation = 0
    /// Set by whoever owns this, and called when the drop is pressed.
    public var onPress: (() -> Void)?

    public init(theme: Theme) {
        state.theme = theme
    }

    public func apply(_ theme: Theme) {
        state.theme = theme
    }

    /// Drops the notch for one finished task.
    ///
    /// Re-showing while one is already out replaces its text and restarts the
    /// clock rather than queueing: three agents finishing inside four seconds
    /// should be one drop that keeps changing, not three drops in a row.
    public func show(_ title: String) {
        guard let screen = Self.screenToUse() else { return }

        generation += 1
        let mine = generation

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(Self.frame(on: screen), display: false)

        state.title = title
        // Only from the top when it is not already out. Re-showing over a drop
        // that is still on screen changes the words on it; sending it back up
        // to come down again with new text is a flinch, not an update.
        if state.progress < 1 {
            state.progress = 0
            panel.orderFrontRegardless()
            withAnimation(.spring(response: Self.slide, dampingFraction: 0.78)) {
                state.progress = 1
            }
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled else { return }
            self?.retract(mine)
        }
    }

    private func retract(_ mine: Int) {
        guard mine == generation else { return }
        withAnimation(.easeIn(duration: Self.slide)) { state.progress = 0 }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.slide + 0.08))
            // Nothing has come out since. Ordering the panel out from under a
            // newer drop is the one way this can go visibly wrong.
            guard let self, mine == generation else { return }
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            // Non-activating, so pressing it does not yank focus away from
            // whatever you were in before the press is even handled.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Above the menu bar, which is level 24. Below the screen saver and
        // below anything a system alert puts up: a drop saying a build finished
        // has no business over a password prompt.
        panel.level = .statusBar
        // It belongs to the screen, not to a space. Following you between
        // desktops is most of the point of putting it at the notch rather than
        // in the window.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = NSHostingView(
            rootView: NotchRoot(state: state) { [weak self] in self?.onPress?() }
        )
        return panel
    }

    /// Where the drop hangs from.
    ///
    /// The panel is the size of the visible part and sits directly under the
    /// bar; the content slides down inside it from its own top edge, so the
    /// panel never resizes and nothing is ever drawn where the notch would
    /// occlude it anyway.
    static func frame(on screen: NSScreen) -> NSRect {
        let top = screen.frame.maxY - Self.barHeight(of: screen)
        return NSRect(
            x: screen.frame.midX - NotchDrop.width / 2,
            y: top - NotchDrop.height,
            width: NotchDrop.width,
            height: NotchDrop.height
        )
    }

    /// What the drop has to clear at the top of the screen.
    ///
    /// On a notched Mac that is the notch, which `safeAreaInsets` gives
    /// exactly. On every other Mac it is the menu bar, and hanging the drop
    /// underneath that is the same gesture in the same place — the machine
    /// simply has nothing sticking down for the top edge to hide behind.
    static func barHeight(of screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        if notch > 0 { return notch }
        return NSStatusBar.system.thickness
    }

    /// The screen with the notch, or the first one.
    ///
    /// Not `NSScreen.main`, which is whichever screen holds the focused window
    /// — so a drop about a build would appear over the second monitor because
    /// that is where the browser happened to be.
    static func screenToUse() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
}
