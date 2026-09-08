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
                        onMoreTools: { model.isQuickActionsVisible = true },
                        recents: model.recentProjects,
                        onOpenProject: { model.openProject($0) }
                    )
                }
            }
            .overlay {
                if model.isDropTarget { DropZoneView() }
            }
            // Said outside the browser, because the browser is a modal you
            // close. Everything the app knew about an install used to live
            // inside it, so closing it took the only evidence with it and what
            // was left was a folder quietly appearing in your home directory.
            .overlay(alignment: .top) {
                if let notice = model.skills.notice {
                    SkillNoticeView(
                        notice: notice,
                        act: { model.skills.dismissNotice(); model.startClaude() },
                        dismiss: { model.skills.dismissNotice() }
                    )
                    .padding(.top, Self.panelGap)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.skills.notice)
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
            //
            // The switch closes the column, not one card in it. The token
            // reading used to stay behind when the task list went — a single
            // card floating in a lane of its own, still taking the width off
            // the terminal, with no way to shut it that was not the ⌘J that
            // had visibly just failed to. ⌘J says "give me the room back",
            // and half the room back is the wrong answer to that.
            //
            // The figure is not lost: it is in the menu bar's menu, one click
            // from anywhere, which is where a number you glance at on your way
            // past belongs when the panel it lived on is closed.
            if !model.tabs.isEmpty, model.isAgentSelected, model.isTaskPanelVisible {
                VStack(spacing: Self.panelGap) {
                    TaskPanelView(tasks: model.tasks) { model.clearTasks() }
                        .frame(maxHeight: .infinity)
                        .panel()
                    // Under the task list, so it carries that card's light
                    // on down rather than starting again. Drawn with no
                    // window too — the card has an empty state, and the
                    // column used to end in a blank while the first request
                    // of a session was still in flight.
                    UsageCardView(usage: model.usage, now: now, place: .bottom)
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
            // Opened from anywhere, agent or not. It used to require one, and
            // closed itself the moment the tab in front of you stopped having
            // one — which meant the screen that explains what a skill is could
            // only be reached by somebody who had already worked it out. What
            // an install needs an agent for is a directory to write into, and
            // that is a question `SkillShelf` can hold open.
            if model.isSkillsVisible {
                ZStack {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { model.isSkillsVisible = false }
                    SkillsView(
                        home: model.skillHome,
                        shelf: model.skills,
                        startClaude: {
                            model.isSkillsVisible = false
                            model.startClaude()
                        },
                        // Typed, not run. The catalogue could not answer, so
                        // the question is handed to the thing that can — and
                        // left at the prompt for the person to send, like
                        // every other command this app puts in front of you.
                        askAgent: { model.typeAtPrompt($0) },
                        close: { model.isSkillsVisible = false }
                    )
                }
                .environment(\.theme, model.themes.theme)
                .transition(.opacity)
            }

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
        .animation(.easeOut(duration: 0.15), value: model.isSkillsVisible)
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        // Published once, here, so every view below reads the same theme.
        .environment(\.theme, model.themes.theme)
        // And whether anything in the window is working, for the light on the
        // panels — see `PanelSheen`. Set beside the theme because it is the
        // same kind of fact: something the whole window is drawn against,
        // which no panel should have to be handed by its parent.
        .environment(\.isWorking, model.isAnythingRunning)
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
    ///
    /// The cases name a *slice of the fall*, not an ordinal, because the two
    /// columns are no longer the same depth: the right-hand column is two
    /// cards and the sidebar is three. `.bottom` is the lower half of a pair;
    /// `.middle` and `.foot` are the second and third of a stack of three. A
    /// single `.bottom` doing both jobs would have to start at two different
    /// colours depending on what happened to be above it.
    enum PanelPlace {
        /// The only card in its column, or the first one down.
        case top
        /// The lower half of a two-card stack.
        case bottom
        /// The second card of three, carrying the fall on without restarting it.
        case middle
        /// The last card of three, and the end of the fall.
        case foot
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
        // Where a three-card stack hands over from its second card to its
        // third: halfway along the same run `.bottom` crosses in one go, so
        // the two depths of column reach the ground by the same route.
        let handover = theme.chrome.panelBottom.mixed(with: theme.ground, by: 0.5)
        let colours = switch place {
        case .top: [theme.chrome.panelTop.color, theme.chrome.panelBottom.color]
        case .bottom: [theme.chrome.panelBottom.color, theme.ground.color]
        case .middle: [theme.chrome.panelBottom.color, handover.color]
        case .foot: [handover.color, theme.ground.color]
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
    /// Whether a card in this position catches light.
    ///
    /// The rule on its own, so it can be checked without rendering anything —
    /// and so that adding a place to `PanelPlace` is a decision about the
    /// light rather than an omission. Only the head of a stack: a card halfway
    /// down a falling gradient has nothing above it for the light to come
    /// from.
    static func catchesLight(_ place: PanelPlace) -> Bool { place == .top }

    /// The light on the top of the stack, in the theme's own colour, brighter
    /// while something is working.
    ///
    /// ## The colour
    ///
    /// It was `chrome.textPrimary` — a text colour, which is near-grey in every
    /// theme by design, so every theme's panels caught the same colourless
    /// light. **The lamp colour is the one the theme actually means by "lit"**:
    /// it is what the wordmark burns, what the meter fills with, and what the
    /// board's `highlight` is a brighter version of. Phosphor's light is amber
    /// now, Matcha's is green, and the top of the window belongs to the theme
    /// rather than to the type.
    ///
    /// ## The breathing
    ///
    /// It rises while any tab is working and settles when they all stop. That
    /// is the one thing the window can say about *itself* rather than about a
    /// tab — the dots, the panel and the menu bar all speak for one session,
    /// and this is the room they are in.
    ///
    /// Slow on purpose, and small: `working` multiplies the theme's own sheen
    /// rather than replacing it, so a theme that lights its panels flat
    /// (`sheen` 0, which Steel does) stays flat while it works. A window that
    /// pulsed regardless of what the theme asked for would be the app
    /// overruling the theme on the largest surface it has.
    struct PanelSheen: View {
        let place: PanelPlace
        @Environment(\.theme) private var theme
        @Environment(\.isWorking) private var isWorking
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// How much brighter the light gets while something is running. Enough
        /// to notice out of the corner of the eye, not enough to read as a
        /// different theme.
        private static let lift: Double = 2.3

        var body: some View {
            if catchesLight(place), theme.shape.sheen > 0 {
                LinearGradient(
                    colors: [
                        theme.board.lit.color
                            .opacity(theme.shape.sheen * (isWorking ? Self.lift : 1)),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isWorking ? 150 : 110)
                .frame(maxHeight: .infinity, alignment: .top)
                // Long, because this is weather rather than a state change —
                // something you notice has happened, not something you watch
                // happen over a terminal you are reading.
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.1),
                    value: isWorking
                )
            }
        }
    }

    /// A panel's whole surface: the fill, the motif on it, and the light
    /// landing on top.
    ///
    /// One builder rather than the `ZStack { panelFill; panelSheen }` that
    /// stood in three files, because the motif has to go *between* those two
    /// layers everywhere. Under the sheen it is part of the material and the
    /// light falls across it; over the sheen it sits on the glass, and the top
    /// of every panel comes out looking dusty.
    @ViewBuilder
    static func panelSurface(_ theme: Theme, at place: PanelPlace) -> some View {
        ZStack {
            panelFill(theme, at: place)
            if let motif = theme.pattern {
                PatternView(motif: motif)
            }
            PanelSheen(place: place)
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
