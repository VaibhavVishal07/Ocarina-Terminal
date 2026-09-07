import AppKit
import SwiftUI

/// The landing screen: shown when every tab has been closed, and on a first
/// launch with nothing installed.
///
/// Top to bottom: the mark, the tools, a button for a plain terminal, and one
/// quiet key. It had seven things on it — a wordmark, a tagline, a heading, a
/// row of dot-matrix plates, a caption explaining the plates, a lit slab saying
/// NEW TERMINAL, and three rows of shortcuts — and seven things competing on an
/// otherwise empty screen is not a landing page, it is a menu with no order to
/// it. What survived is either the app saying its own name or something you can
/// press, and the order they are in is the order somebody wants them.
///
/// The mark stays in dot matrix because that is the one piece of pure identity
/// Ocarina has. Everything under it is ordinary type and ordinary icons,
/// because it is ordinary interface, and drawing a tool's name in a 5x7 grid
/// made it look like part of the logo rather than part of the list.
struct EmptyStateView: View {
    let onNewTab: () -> Void
    /// Press a tool: open it if it is here, install it if it is not.
    let onPickAgent: (AgentTool) -> Void
    /// The "+", which hands over to the full drawer.
    let onMoreTools: () -> Void

    /// Which agents are on this machine.
    ///
    /// Read when the screen appears rather than held from launch. This is
    /// exactly where you land after an install — you close the tab it ran in
    /// and arrive back here — so a value cached at launch would tell you the
    /// thing you just watched arrive is not here.
    @State private var installed: Set<String> = []
    @State private var isHovered = false
    /// When the flurry ends, and with it the theme's own line. Set by pressing
    /// the wordmark; nil the rest of the time. See `Trinket`.
    @State private var flurryUntil: Date?

    // The board is the app's one piece of pure identity, so it is themed
    // rather than fixed: a Sakura board is pink dots on pale, an Ocarina board
    // is the blue it always was, and both come from the same five slots.
    @Environment(\.theme) private var theme

    private var backdrop: Color { theme.board.backdrop.color }
    private var unlit: Color { theme.board.unlit.color }
    private var lit: Color { theme.board.lit.color }
    private var litDim: Color { theme.board.litDim.color }

    var body: some View {
        ZStack {
            backdrop.opacity(0.62).ignoresSafeArea()

            if let trinket = theme.trinket {
                TrinketField(trinket: trinket, colour: lit, flurryUntil: flurryUntil)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                DotMatrixText(
                    text: "OCARINA",
                    cell: 4.4,
                    gap: 1.6,
                    lit: lit,
                    unlit: unlit
                )
                // The one thing on this screen that does nothing, so it is the
                // one thing that can afford to do something. Pressing it throws
                // a flurry of the theme's trinket and lets the theme say its
                // own line where the tagline was.
                .contentShape(.rect)
                .onTapGesture { flurry() }

                DotMatrixText(
                    text: tagline,
                    cell: 1.9,
                    gap: 0.85,
                    lit: isFlurrying ? lit : litDim,
                    unlit: unlit,
                    glow: false
                )
                .padding(.top, 12)

                // One line, and only for somebody who has nothing yet. A
                // repeat user does not need to be told what a row of their own
                // tools is; a first-time user has never seen any of these
                // three names and needs to know the row is a choice.
                if installed.isEmpty {
                    Text("Pick a tool to install. One click does the rest.")
                        .font(theme.uiFont(12.5, weight: .medium))
                        .foregroundStyle(theme.chrome.textSecondary.color)
                        .padding(.top, 40)
                        .padding(.bottom, -12)
                }

                AgentDock(
                    installed: installed,
                    onPick: onPickAgent,
                    onMore: onMoreTools
                )
                .padding(.top, 44)

                callToAction
                    .padding(.top, 40)

                quickActions
                    .padding(.top, 18)
            }
        }
        .onAppear { installed = AgentCatalog.installedIDs() }
        // And again when the app comes back to the front, which is what
        // happens when the install was done anywhere other than in here.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            installed = AgentCatalog.installedIDs()
        }
    }

    /// The tagline, or the theme's own line while the flurry lasts.
    ///
    /// A theme with no line of its own keeps the app's, which is the right
    /// answer rather than a gap: pressing the wordmark still does something,
    /// and what it does is the trinket.
    private var tagline: String {
        guard isFlurrying, let flavour = theme.flavour else {
            return "SONG OF A NEW TERMINAL"
        }
        return flavour
    }

    private var isFlurrying: Bool {
        guard let flurryUntil else { return false }
        return flurryUntil > .now
    }

    /// Throws the flurry, and takes it back when it is over.
    ///
    /// The timer is what puts the tagline back — the trinket field works out
    /// its own fade from the deadline, but a `String` cannot, so something has
    /// to come back and ask. Pressing again restarts it rather than stacking.
    private func flurry() {
        let until = Date.now.addingTimeInterval(TrinketField.flurry)
        withAnimation(.easeOut(duration: 0.2)) { flurryUntil = until }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TrinketField.flurry))
            // Only if nothing has been pressed since: a second press while the
            // first is still running owns the deadline now.
            guard flurryUntil == until else { return }
            withAnimation(.easeOut(duration: 0.4)) { flurryUntil = nil }
        }
    }

    /// The way out of the row above: a plain terminal, no agent involved.
    ///
    /// A real button again, after a spell as one word in a line of small grey
    /// text. Cutting it that far was overcorrecting for the lit slab it used to
    /// be — that slab was the biggest object on the screen, which said opening
    /// a bare shell was the main event on the day you install this, and it is
    /// not. But it is still the second thing anybody wants from a terminal app,
    /// and the second thing should look like something you can press.
    ///
    /// So it sits under the tools rather than over them, and it is drawn in the
    /// accent at a quarter strength — present, clearly a button, and not
    /// competing with four icons that each do more.
    private var callToAction: some View {
        Button(action: onNewTab) {
            HStack(spacing: 9) {
                Image(systemName: "terminal")
                    .font(theme.uiFont(12, weight: .semibold))
                Text("Open new terminal")
                    .font(theme.uiFont(13, weight: .semibold))
                Text("\u{2318}T")
                    .font(theme.uiFont(11, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            .foregroundStyle(theme.chrome.textPrimary.color)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.chrome.accent.color.opacity(isHovered ? 0.24 : 0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                theme.chrome.accent.color.opacity(isHovered ? 0.6 : 0.38),
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    /// The one key left that is worth naming here, and it presses too.
    private var quickActions: some View {
        key("Quick actions", "\u{2318}K", action: onMoreTools)
    }

    private func key(_ title: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(theme.uiFont(12, weight: .medium))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                Text(shortcut)
                    .font(theme.uiFont(11, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
