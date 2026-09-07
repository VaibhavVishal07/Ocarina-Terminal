import AppKit
import OcarinaTerminalContext
import SwiftUI

public struct OcarinaWindowView: View {
    /// The smallest the window may get. Below this the sidebar is pushed off
    /// the window's left edge and clipped — the tab names lose their first
    /// characters and the rows look jammed into the corner — so the window is
    /// held to it rather than the content merely refusing to shrink.
    public static let minimumSize = CGSize(width: 900, height: 440)

    /// The gap around the panels, and between them.
    ///
    /// One number for both, because a card floating in a window and two cards
    /// floating beside each other are the same relationship seen twice — the
    /// moment the outer gap and the inner gap differ, the pair stops reading as
    /// a set and starts reading as a mistake.
    static let panelGap: CGFloat = 10

    /// One width for both side panels.
    ///
    /// They were 165 and 230, which read as two different kinds of thing
    /// rather than two of the same thing — and the narrow one was the one that
    /// needed the room: at 165 a generated tab name got about 77pt, some
    /// twelve characters, so nearly every name in the column arrived already
    /// cut. Equal, and the sidebar gains half its width again.
    static let panelWidth: CGFloat = 230

    /// The panels' corner is the theme's now — see `Theme.Shape` — and this
    /// is what a theme that says nothing gets. Continuous rather than
    /// circular, like the rows inside them: at this size the difference
    /// between the two is the whole difference between drawn and stamped out.
    static let panelCorner: CGFloat = CGFloat(Theme.Shape.houseCorner)

    /// The terminal's gap from the left edge of its card.
    ///
    /// 16 rather than 18 because the terminal cell carries about 2pt of its
    /// own to the left of the first glyph. Measured off the rendered window,
    /// 16 here is the 18 you see. It was 22 against the window's own edge;
    /// inside a card that already floats 10pt off that edge, 22 more put the
    /// first column a third of the way to the sidebar.
    private static let terminalInset: CGFloat = 16

    /// The gap above the first line and below the last.
    ///
    /// Equal, and both measured from the *card*, which is what changed: there
    /// is no titlebar overhead to allow for any more, so the top no longer
    /// needs a different number from the bottom. Before this the first line
    /// sat some 50pt down a window whose last line was flush against the
    /// bottom edge — the text was visibly high in its own bed.
    private static let terminalVerticalInset: CGFloat = 14

    private let model: OcarinaModel

    /// Drives the usage card's countdown. A minute is the finest thing it
    /// shows, so a minute is how often it needs waking.
    @State private var now = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    public init(model: OcarinaModel) {
        self.model = model
    }

    /// Read from the store, not from the environment.
    ///
    /// This view is the one that *publishes* the theme, and `.environment` only
    /// reaches descendants — a view cannot read a value it sets on itself. Doing
    /// so silently handed the terminal's bed the compiled-in fallback while
    /// every view below it drew the chosen theme, so a light theme came up with
    /// a pale sidebar against a near-black terminal.
    private var theme: Theme { model.themes.theme }

    public var body: some View {
        @Bindable var model = model
        return HStack(spacing: Self.panelGap) {
            // With nothing open there is no list to draw: the empty state gets
            // the whole window rather than sitting beside an empty sidebar.
            if !model.tabs.isEmpty {
                // No `.panel()` here: the sidebar draws its own card, because
                // a tool tip has to be able to hang off the edge of it and a
                // clip would take the half that hangs.
                TabSidebarView(model: model)
                    // A tool tip hangs off the sidebar's edge, and the terminal
                    // is drawn after it in the stack.
                    .zIndex(1)
            }

            ZStack {
                // Not fully opaque: the terminal view itself is clear, so the
                // bed colour inside this is the only thing between the text
                // and the window's glass. See `TerminalBed` for what is drawn
                // over it and why none of it is anything to look at.
                TerminalBed(activity: model.selectedActivity)
                    .environment(\.theme, theme)
                if let session = model.selectedSession {
                    // The terminal had no inset at all: the first column sat on
                    // the window edge (clipping its left half) and the top line
                    // ran under the titlebar.
                    //
                    // Four numbers rather than one, because the four edges are
                    // not the same edge. The top already has the titlebar's
                    // safe area under it and needs breathing room, not
                    // clearance; the bottom has nothing under it at all and
                    // needs the margin outright; the trailing side leaves the
                    // scrollbar its lane. See each constant for its own
                    // reasoning.
                    TerminalHostView(session: session)
                        .id(session.id)
                        .padding(.leading, Self.terminalInset)
                        // The scroller's lane. It only appears while you are
                        // scrolling now, but it appears *over* the trailing
                        // edge, and text running under a knob that fades in is
                        // worse than text that stops a few points short.
                        .padding(.trailing, 8)
                        .padding(.vertical, Self.terminalVerticalInset)
                } else {
                    EmptyStateView(
                        onNewTab: { model.newTab() },
                        onPickAgent: { model.start($0) },
                        onMoreTools: { model.isQuickActionsVisible = true }
                    )
                }
            }
            .overlay {
                if model.isDropTarget { DropZoneView() }
            }
            .overlay(alignment: .top) {
                if let code = model.selectedFailure, model.isErrorBannerVisible {
                    ErrorBannerView(
                        exitCode: code,
                        hasAgent: ErrorHelp.installedAgent() != nil,
                        explain: { model.explainLastFailure() },
                        dismiss: { model.isErrorBannerVisible = false }
                    )
                    // Inside its own card now, rather than clearing a titlebar
                    // the content used to run under.
                    .padding(.top, Self.panelGap)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.selectedFailure)
            .panel()

            // A column again, and a permanent one. It was an overlay only so it
            // could animate in without resizing the terminal — every frame of
            // that resize being an `ioctl(TIOCSWINSZ)` and a SIGWINCH. Nothing
            // animates now, so the terminal is laid out once, at its real width,
            // and the panel covers none of it.
            // No animation on this. Showing the column resizes the terminal,
            // and animating that resize is what made the old drawer judder: a
            // SIGWINCH per frame, the shell repainting through the whole slide.
            // The right-hand column: the task list, and under it what this
            // agent has spent — the shorter list is what pays for the card,
            // which is the trade the card is worth.
            //
            // The card that briefly sat here instead said what the agent was
            // doing right now, and that reading was already on the screen in
            // three places: the tab's dot, the rail over the terminal, and the
            // row in the list above it. It is in the menu bar now, which is
            // where it is worth anything — the question "is it still going" is
            // one you have while you are looking at something else. See
            // `ActivityStatusItem`.
            //
            // Gone entirely unless there is an agent in front of you.
            //
            // Both panels are *about* an agent conversation — what has been
            // asked of it, what it has spent — so a shell at a prompt has
            // nothing to put in either. It used to open on launch regardless
            // and sit there saying "No tasks yet" at somebody who had not yet
            // started an agent and had no way to know that was the point.
            if !model.tabs.isEmpty, model.isAgentSelected,
               model.isTaskPanelVisible || model.usage != nil {
                VStack(spacing: Self.panelGap) {
                    if model.isTaskPanelVisible {
                        TaskPanelView(tasks: model.tasks) { model.clearTasks() }
                            .frame(maxHeight: .infinity)
                            .panel()
                    }
                    // Under the task list, so it carries that card's light
                    // on down rather than starting again. Drawn with no
                    // window too — the card has an empty state, and the
                    // column used to end in a blank while the first request
                    // of a session was still in flight.
                    UsageCardView(
                        usage: model.usage,
                        now: now,
                        place: model.isTaskPanelVisible ? .bottom : .top
                    )
                    .panel()
                }
                .frame(width: Self.panelWidth)
            }
        }
        // Panels appear and disappear, they do not travel.
        //
        // Showing or hiding a column resizes the terminal, and every frame of
        // an animated resize is an `ioctl(TIOCSWINSZ)` and a SIGWINCH — the
        // shell repainting itself through the whole slide, which is what made
        // the old drawer judder. The task panel already knew this; the sidebar
        // and the usage card were still inheriting an animation from further
        // up the view tree. Nothing in this stack animates now.
        .transaction { $0.animation = nil }
        // The gap that makes them float: the same on all four sides as it is
        // between them.
        .padding(Self.panelGap)
        // And the ground it floats on, in the theme rather than in the
        // system's own grey. The gap used to show the raw `NSVisualEffectView`
        // straight through, so a themed window sat in a frame that belonged to
        // no theme at all. Not quite opaque, so the material underneath still
        // carries what is behind the window — which is the whole reason the
        // backdrop is there.
        .background(theme.ground.color.opacity(0.94).ignoresSafeArea())
        // Not a sheet. A sheet on macOS is modal and will not dismiss on a
        // click outside it, and picking a theme is a thing you do by trying
        // three and then getting on with your work.
        .overlay {
            if model.isThemePickerVisible {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { model.isThemePickerVisible = false }
                    ThemePickerView(model: model) { model.isThemePickerVisible = false }
                }
                .environment(\.theme, model.themes.theme)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isThemePickerVisible)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        // Published once, here, so every view below reads the same theme.
        .environment(\.theme, model.themes.theme)
        .onAppear {
            model.start()
            model.applyThemeToSessions()
            Self.matchSystemAppearance(to: model.themes.theme)
            Self.tintWindows(with: model.themes.theme)
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: model.themes.selectedID) { _, _ in
            model.applyThemeToSessions()
            Self.matchSystemAppearance(to: model.themes.theme)
            Self.tintWindows(with: model.themes.theme)
        }
        .sheet(isPresented: $model.isCommandPaletteVisible) {
            CommandPaletteView(model: model)
        }
        .sheet(item: $model.pendingPaste) { reading in
            PasteReviewView(
                reading: reading,
                paste: { model.confirmPendingPaste() },
                cancel: { model.pendingPaste = nil }
            )
            .environment(\.theme, model.themes.theme)
        }
        .sheet(isPresented: $model.isQuickActionsVisible) {
            QuickActionsView(model: model)
                .environment(\.theme, model.themes.theme)
        }
        .sheet(isPresented: $model.isFeedbackVisible) {
            FeedbackView(
                openIssue: { model.openFeedbackIssue($0) },
                copy: { model.copyFeedback($0) },
                cancel: { model.isFeedbackVisible = false }
            )
            .environment(\.theme, model.themes.theme)
        }
    }

    /// Where a panel sits in a stack, which is what decides how it is lit.
    enum PanelPlace {
        /// The only card in its column, or the first one down.
        case top
        /// Under another card, and carrying the light on down.
        case bottom
    }

    /// The fill a stacked panel is drawn in.
    ///
    /// One gradient across the whole column, cut into pieces. Two cards each
    /// running their own top-to-bottom gradient made the column go bright,
    /// dim, bright, dim — the light restarted at every card, and the pair read
    /// as two objects that happened to be near each other.
    ///
    /// Mirroring the lower one was tried and is wrong for the same reason in
    /// reverse: the junction matched, but the column then got *brighter* on
    /// the way down, which is not what a light source does. So the top card
    /// runs from the panel colour to its dark end, and the card below carries
    /// on from that dark end down towards the window's own ground. The stack
    /// darkens all the way, once.
    static func panelFill(_ theme: Theme, at place: PanelPlace) -> LinearGradient {
        let colours = switch place {
        case .top: [theme.chrome.panelTop.color, theme.chrome.panelBottom.color]
        case .bottom: [theme.chrome.panelBottom.color, theme.ground.color]
        }
        return LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
    }

    /// The sheen: light landing on the top of the stack, and nowhere else.
    ///
    /// Drawn in the theme's own text colour rather than always in white — on a
    /// pale panel a white highlight is invisible and a dark one reads. A card
    /// halfway down a column has no reason to catch light of its own; putting
    /// one there is what made the second card glow in the middle of a gradient
    /// that was supposed to be falling.
    /// How hard the light lands is the theme's to say: `Theme.Shape.sheen`
    /// scales the house 0.035, and a theme that wants its panels lit flat sets
    /// it to zero.
    @ViewBuilder
    static func panelSheen(_ theme: Theme, at place: PanelPlace) -> some View {
        if place == .top, theme.shape.sheen > 0 {
            LinearGradient(
                colors: [theme.chrome.textPrimary.color.opacity(theme.shape.sheen), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Rounds a panel off and draws its edge.
    ///
    /// No drop shadow. The gap and the hairline are what say a panel is a
    /// separate surface; a shadow under each of three cards in a window this
    /// size reads as depth for its own sake, and it has to be fought off every
    /// overlay that leaves the panel it belongs to.
    struct PanelStyle: ViewModifier {
        @Environment(\.theme) private var theme

        /// The house cut. Every panel takes the same one — a radius that
        /// moved with the theme made each theme look like its own app.
        static var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: panelCorner, style: .continuous)
        }

        func body(content: Content) -> some View {
            content
                .clipShape(Self.shape)
                .overlay {
                    Self.shape
                        .stroke(theme.chrome.border.color.opacity(0.16), lineWidth: 1)
                }
        }
    }

    /// The titlebar is the one surface SwiftUI cannot reach.
    ///
    /// It is drawn by the window, above the content view, so a background in
    /// the view hierarchy stops at the bar and leaves it standing in system
    /// grey over a themed window. `titlebarAppearsTransparent` hands it the
    /// window's own background colour instead, which is this — and the
    /// separator is asked for explicitly, because transparency takes the
    /// hairline with it and that line is the border the panels sit under.
    private static func tintWindows(with theme: Theme) {
        for window in NSApp.windows where window.contentView != nil {
            window.backgroundColor = theme.ground.nsColor
            window.titlebarSeparatorStyle = .line
        }
    }

    /// System controls draw themselves — the keep-awake switch, menus, the
    /// window's own furniture — and they take their cue from `NSAppearance`,
    /// not from us. Without this a light theme keeps a dark switch and dark
    /// scrollbars, which reads as a half-finished theme rather than a choice.
    private static func matchSystemAppearance(to theme: Theme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

extension View {
    /// Makes a view read as one of the window's floating panels.
    func panel() -> some View { modifier(OcarinaWindowView.PanelStyle()) }
}
