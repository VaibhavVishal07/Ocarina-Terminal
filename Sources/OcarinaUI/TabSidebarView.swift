import AppKit
import SwiftUI

/// The tab list, down the side.
///
/// Tabs went across the top while they were few and short. They are neither:
/// naming gives every tab a sentence-shaped name, and the whole point of the
/// app is keeping a column of them. Horizontally that meant each name was cut
/// to 24 characters and the strip scrolled sideways past the ones that did not
/// fit. Vertically the list has the room to be long, which is what a task list
/// needs, and the terminal keeps the width it lost to the strip's full span.
struct TabSidebarView: View {
    /// The shared side-panel width. It was 165 — narrow on purpose, on the
    /// argument that the terminal is what the window is for — but the names
    /// this app generates are up to four words, and 165 left about 77pt for
    /// them. Twelve characters. Nearly every name in the column arrived
    /// already cut, which is not a column you can pick a tab out of.
    static let width: CGFloat = OcarinaWindowView.panelWidth
    /// Only catches pathological names — the width truncates long ones long
    /// before this does.
    static let titleLimit = 34
    /// The close button's glyph size and the diameter of the circle behind it.
    /// The slot is reserved whether or not the button is in it, so a row does
    /// not reflow as the pointer arrives.
    private static let badgeSize: CGFloat = 18
    private static let badgeGlyph: CGFloat = 9
    /// Rows sit in from the panel's edges rather than running up against them,
    /// by the same amount on every side. Flush against the side, a selected row
    /// read as a slab wedged into the corner instead of a card resting on the
    /// panel.
    private static let inset: CGFloat = 10
    /// Continuous rather than circular: the squircle's curvature eases in
    /// instead of meeting the straight edge at a tangent, which is what stops
    /// a rounded rectangle this size from looking stamped out.
    private static let rowCorner: CGFloat = 10
    /// One height for everything in the list, tabs and the new-tab button
    /// alike.
    ///
    /// It was 32, and 32 was a floor rather than a taste: hovering used to add
    /// a 9.5pt subtitle under the name, and the row had to be tall enough to
    /// absorb it so the list did not shift as the pointer arrived. The
    /// subtitle is gone, and with it the constraint — so the height is now
    /// chosen for how a row should sit rather than for what it has to swallow.
    /// A name needs air around it more than the column needs another two rows
    /// on screen.
    private static let rowHeight: CGFloat = 40

    /// Extra air between a settings row's glyph and its label, on top of the
    /// stack's own 7.
    ///
    /// The marks in this card are simple ones — a half-filled circle, a
    /// bubble, three lines, a bolt — and a simple mark set tight against a
    /// word reads as a bullet in front of it rather than as an icon beside
    /// it. The gap is what makes the glyphs a column of their own.
    private static let glyphGap: CGFloat = 8

    /// And a tighter one for the settings card.
    ///
    /// A tab row is 40 because a name wants air around it. Four settings in a
    /// stack want the opposite: at 40 apiece they took 160pt off the bottom of
    /// the column — a sixth of the window — to say four short words.
    ///
    /// Fixed rather than a minimum. As a minimum the two rows carrying a switch
    /// came out taller than the two carrying a link — the control has an
    /// intrinsic height of its own and the row grew to it — so a card of four
    /// identical rows rendered as four different ones.
    private static let settingsRowHeight: CGFloat = 27

    @Environment(\.theme) private var theme
    @Bindable var model: OcarinaModel
    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var draftTitle: String = ""
    @FocusState private var isRenameFocused: Bool
    @State private var toolTip: ToolTipTarget?
    @State private var isNewTabHovered = false
    @State private var isThemeHovered = false
    @State private var isFeedbackHovered = false
    @State private var isSkillsHovered = false

    private static let space = "tabsidebar"


    /// Two cards, not one.
    ///
    /// The tabs and the settings were a single panel with the settings drawn
    /// as an inset box inside it — a card in a card, which is a shape the rest
    /// of the window does not use anywhere. The right-hand column had already
    /// answered this: the task list and the token widget are two separate
    /// panels with the window's ground between them. This is the same answer
    /// on the other side, so the four panels in the window are four of the
    /// same kind of object rather than three and a nested one.
    var body: some View {
        VStack(spacing: OcarinaWindowView.panelGap) {
            listCard
            settingsCard
        }
        .frame(width: Self.width)
        .coordinateSpace(name: Self.space)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if let toolTip {
                    ToolTipBubble(
                        target: toolTip,
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                }
            }
        }
    }

    /// The mark and the list of tabs.
    private var listCard: some View {
        VStack(spacing: 0) {
            // Breathing room at the top of the card.
            Color.clear.frame(height: Self.inset)

            wordmark
                // The icon column, not the row's outer edge: the status
                // dots, the plus and the palette all start at inset + 7,
                // and the mark reading against that line is the only thing
                // that makes it look placed rather than dropped in.
                .padding(.leading, Self.inset + 7)
                .padding(.trailing, Self.inset)
                // On top of the spacer above, so the mark sits a clear step
                // inside the card rather than against its top edge.
                .padding(.top, 10)
                .padding(.bottom, 24)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        row(for: tab)
                    }
                    // Below the last tab, not above the first: the button is
                    // where the next tab will appear, and it travels with the
                    // list rather than sitting over it.
                    newTabButton
                }
                .padding(.horizontal, Self.inset)
                .padding(.bottom, Self.inset)
            }
        }
        // The list gives way, and the settings never do. Without this the
        // scroller kept its full height once there were enough tabs to fill
        // it and the card below was pushed off the bottom of the window —
        // the tabs ran straight into Theme and Share Feedback.
        .frame(maxHeight: .infinity)
        .layoutPriority(0)
        .background(card(at: .top))
    }

    /// The surface both cards are drawn on.
    ///
    /// A background rather than a clip: the tool tips are an overlay on this
    /// view and they are meant to hang off its edge, so clipping the sidebar
    /// would cut every one of them in half. That is also why neither card uses
    /// `panel()`, which clips.
    private func card(at place: OcarinaWindowView.PanelPlace = .top) -> some View {
        metal(at: place)
            .clipShape(OcarinaWindowView.PanelStyle.shape)
            .overlay {
                OcarinaWindowView.PanelStyle.shape
                    .stroke(theme.chrome.border.color.opacity(0.16), lineWidth: 1)
            }
    }

    // MARK: - Surface

    /// Dark metal, not glass. Translucent material let whatever sat behind the
    /// window through, and the sheen over it made the column the brightest
    /// thing on a screen whose other half is a nearly black terminal. This is
    /// an opaque dark panel with one faint highlight along the top — enough to
    /// read as a brushed surface catching light, not enough to shine.
    private func metal(at place: OcarinaWindowView.PanelPlace) -> some View {
        OcarinaWindowView.panelSurface(theme, at: place)
            .allowsHitTesting(false)
    }

    // MARK: - New tab

    /// The one row in the column that answered to nothing: every tab lights up
    /// under the pointer and this did not, so it read as a label rather than a
    /// button. It takes the row's hover treatment exactly — same fill, same
    /// edge, same corner — because it is the same shape in the same list.
    private var newTabButton: some View {
        Button {
            model.newTab()
        } label: {
            HStack(spacing: 7) {
                // The plus takes the status dot's column, so "New Tab" starts
                // on the same left edge as a plain shell tab's name.
                Image(systemName: "plus")
                    .font(theme.uiFont(10.5, weight: .bold))
                    .frame(width: 9)
                Text("New Tab")
                    .font(theme.uiFont(12, weight: .medium))
                Spacer(minLength: 0)
                Text("\u{2318}T")
                    .font(theme.uiFont(10.5, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            .foregroundStyle(isNewTabHovered
                             ? theme.chrome.textPrimary.color
                             : theme.chrome.textSecondary.color)
            .padding(.horizontal, 7)
            .frame(minHeight: Self.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                    .fill(theme.chrome.rowHover.color.opacity(isNewTabHovered ? 0.07 : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                            .stroke(theme.chrome.border.color.opacity(isNewTabHovered ? 0.10 : 0),
                                    lineWidth: 1)
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isNewTabHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isNewTabHovered)
        .padding(.top, 3)
    }

    // MARK: - Settings

    /// Theme, feedback, the task panel and keep-awake, in one card.
    ///
    /// They were two loose stacks with a rule between them, sitting directly
    /// on the sidebar's own surface — so with enough tabs open the list ran
    /// into them and there was nothing to say where the list stopped and the
    /// settings began. One card, edged like the token widget across the
    /// window, is that edge; and it is one object for the layout to keep hold
    /// of rather than four rows to push around.
    private var settingsCard: some View {
        VStack(spacing: 1) {
            // Always, and above Theme because it is the one row here that is
            // about the work rather than about the app.
            //
            // It used to appear only with an agent in front of you, on the
            // reasoning that a skill installs into an agent's directory and a
            // plain shell has none. What that produced was a row that was
            // missing on the day somebody most needed it: you find out what a
            // skill is by opening this, and you could not open it until you
            // had already started the agent the skills are for. The install
            // still needs a directory; the browser does not, and a press with
            // nowhere to put it is held by `SkillShelf` until there is.
            //
            // The trailing value is how many you have, counting the ones
            // waiting for an agent. It was the agent's name — which answered
            // "skills for what", a question the browser now answers at its own
            // foot, and left the row with nothing to say about whether you had
            // any.
            Button {
                model.isSkillsVisible = true
            } label: {
                footerRow(
                    symbol: "square.stack",
                    title: "Skills",
                    trailing: model.skills.total > 0 ? "\(model.skills.total)" : "",
                    hovered: isSkillsHovered
                )
            }
            .buttonStyle(.plain)
            .onHover { isSkillsHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isSkillsHovered)

            // Opens the picker rather than a list of names: choosing a look
            // from words asks you to remember what Matcha looked like.
            Button {
                model.isThemePickerVisible = true
            } label: {
                footerRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Theme",
                    // Not the theme's name. The window is *wearing* the theme —
                    // the answer is the thing you are looking at, and printing
                    // it as well spent the row's whole trailing edge repeating
                    // what every other pixel already said.
                    trailing: "",
                    hovered: isThemeHovered
                )
            }
            .buttonStyle(.plain)
            .onHover { isThemeHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isThemeHovered)

            // Under Theme rather than buried in a menu: the people this app is
            // for are the ones least likely to go looking for where to complain.
            Button {
                model.isFeedbackVisible = true
            } label: {
                footerRow(
                    symbol: "bubble.left",
                    title: "Share Feedback",
                    trailing: "",
                    hovered: isFeedbackHovered
                )
            }
            .buttonStyle(.plain)
            .onHover { isFeedbackHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isFeedbackHovered)

            switchRow(
                symbol: "list.bullet",
                title: "Tasks",
                shortcut: "\u{2318}J",
                isOn: Binding(
                    get: { model.isTaskPanelVisible },
                    set: { model.setTaskPanel(visible: $0) }
                )
            )

            switchRow(
                symbol: "bolt",
                title: "Keep Awake",
                shortcut: nil,
                isOn: Binding(
                    get: { model.sleepGuard.isEnabled },
                    set: { isOn in
                        model.sleepGuard.isEnabled = isOn
                        TactileClick.shared.play(.down)
                    }
                ),
                // The tip hangs off the label, not the row. Over the switch it
                // would be explaining a control you are already using, and the
                // switch is an AppKit view with tracking of its own — leaving
                // the row *from* the switch swallowed the exit, and the bubble
                // stayed up until something else replaced it.
                tip: sleepHelp
            )
        }
        // The count changes as skills go in and come out. Eased, so a row
        // whose trailing edge gains a figure does not read as a flicker.
        .animation(.easeOut(duration: 0.16), value: model.skills.total)
        // The rows sit in from the card's edges by the same amount the tab
        // rows sit in from theirs, so the two cards' contents line up down the
        // column rather than each starting somewhere of its own.
        .padding(.horizontal, Self.inset)
        .padding(.vertical, Self.inset - 2)
        .layoutPriority(1)
        .background(card(at: .bottom))
    }

    /// The app's mark, in the board's own alphabet.
    ///
    /// The same `DotMatrixText` the empty state is built from, which is the one
    /// piece of pure identity Ocarina has — so the window carries it whether or
    /// not there is a terminal open, rather than only when there is nothing to
    /// show.
    ///
    /// A mark, not a headline. Seven characters is 41 cells across, so a 1.4pt
    /// cell on a 0.7pt gap comes to 85pt in a 145pt column — a bit over half its
    /// width, which is where a signature sits without competing with the list
    /// underneath it.
    ///
    /// Lit, and with the bloom on, the same as the empty state's board: the mark
    /// is the app's one piece of pure identity and a greyed-out logo is a logo
    /// that has been switched off. It was the size that made it shout, not the
    /// brightness — 85pt of it does not compete with the list the way 122 did.
    ///
    /// The titlebar's own "Ocarina" is hidden in `main.swift`, or the window
    /// would wear its name twice, ten points apart.
    /// It runs the website's chase while an agent is working in any tab. The
    /// mark sits over the list of every tab, so it is the one thing in the
    /// window that can say "something is still going" about a tab you are not
    /// looking at — and it says it by lighting its own lamps, which costs the
    /// column no room and adds no second spinner to a window that already has
    /// one in the menu bar.
    private var wordmark: some View {
        DotMatrixText(
            text: "OCARINA",
            cell: 1.4,
            gap: 0.7,
            lit: theme.board.lit.color,
            unlit: theme.board.unlit.color,
            chase: model.isAnythingRunning
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Same shape as a tab row, because it is the same list.
    private func footerRow(
        symbol: String,
        title: String,
        trailing: String,
        hovered: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(theme.uiFont(10.5, weight: .medium))
                .frame(width: 9)
                // On the icon rather than on the stack's spacing: that gap is
                // also what sits between the label and the value, and widening
                // it pushed those two apart as well.
                .padding(.trailing, Self.glyphGap)
            // The label names the row, so it is never the thing that gets cut.
            // `fixedSize` on the *value* meant the opposite: a long value —
            // "High Contrast", when this row still printed the theme's name —
            // overran the column, and what gave way was "Theme", which
            // rendered as "The…".
            Text(title)
                .font(theme.uiFont(12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            // The value takes the squeeze instead, and takes it by shrinking
            // rather than by losing its tail: a theme is picked by name, and
            // "High Contra…" is a worse thing to read than a point of type.
            Text(trailing)
                .font(theme.uiFont(10.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
        }
        .foregroundStyle(hovered ? theme.chrome.textPrimary.color
                                 : theme.chrome.textSecondary.color)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: Self.settingsRowHeight, maxHeight: Self.settingsRowHeight)
        .background {
            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                .fill(theme.chrome.rowHover.color.opacity(hovered ? 0.07 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                        .stroke(theme.chrome.border.color.opacity(hovered ? 0.10 : 0), lineWidth: 1)
                }
        }
        .contentShape(.rect)
    }

    // MARK: - Keep awake

    /// Ocarina holds the display awake while it is open, which is a thing a
    /// machine does silently and inexplicably unless something says so. The
    /// state gets one short line — at this width a paragraph became six
    /// wrapped lines that nobody reads twice.
    /// A stock `.switch` draws itself in the system accent, which made the one
    /// saturated object in the window a setting you touch about twice a month.
    /// It sat at the bottom of a column of muted greys and pulled the eye down
    /// there and held it.
    ///
    /// Turning the switch grey would only have made it look disabled, so the
    /// control is gone instead of recoloured. The row already had two things
    /// saying what the state was — the cup fills when the assertion is held,
    /// and the line underneath says it in words — so the switch was the third,
    /// and the loudest, and the only one that needed a colour. The whole row
    /// is the target now, lighting up under the pointer exactly like a tab
    /// does, with On or Off where the switch used to be.
    private var sleepPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(theme.chrome.border.color.opacity(0.12))
                .frame(height: 1)
                .padding(.bottom, 6)

            // Both rows are built like the Theme row above them, because they
            // are the same kind of row. They were not: one sat at inset+inset
            // and one at inset+7, against a Theme label at inset+7+9+7, so the
            // three settings had three different left edges.
            switchRow(
                symbol: "list.bullet",
                title: "Tasks",
                shortcut: "\u{2318}J",
                isOn: Binding(
                    get: { model.isTaskPanelVisible },
                    set: { model.setTaskPanel(visible: $0) }
                )
            )
            .padding(.bottom, 2)

            switchRow(
                symbol: "bolt",
                title: "Keep Awake",
                shortcut: nil,
                isOn: Binding(
                    get: { model.sleepGuard.isEnabled },
                    set: { isOn in
                        model.sleepGuard.isEnabled = isOn
                        TactileClick.shared.play(.down)
                    }
                ),
                // The tip hangs off the label, not the row. Over the switch it
                // would be explaining a control you are already using, and the
                // switch is an AppKit view with tracking of its own — leaving
                // the row *from* the switch swallowed the exit, and the bubble
                // stayed up until something else replaced it.
                tip: sleepHelp
            )
        }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
    }

    /// A settings row with a switch, laid out exactly like `footerRow`: a 9pt
    /// symbol column at inset + 7, and the label after it. Sharing the geometry
    /// is the point — these sit directly under the Theme row and any difference
    /// in the left edge is visible as a ragged column.
    private func switchRow(
        symbol: String,
        title: String,
        shortcut: String?,
        isOn: Binding<Bool>,
        tip: String? = nil
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(theme.uiFont(10.5, weight: .medium))
                .frame(width: 9)
                .padding(.trailing, Self.glyphGap)
                .foregroundStyle(theme.chrome.textTertiary.color)

            Group {
                if let tip {
                    Text(title)
                        .contentShape(.rect)
                        .toolTip(tip, in: Self.space, target: $toolTip)
                } else {
                    Text(title)
                }
            }
            .font(theme.uiFont(11.5, weight: .medium))
            .foregroundStyle(theme.chrome.textSecondary.color)
            .lineLimit(1)
            .fixedSize()

            // Always present, empty when there is no key. As a conditional the
            // two rows had a different number of children and the switch on one
            // of them settled 2pt right of the other.
            Text(shortcut ?? "")
                .font(theme.uiFont(10.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .fixedSize()

            // Small on purpose. The switch is laid over the row, so this only
            // has to stop the label running under it — and a large minimum is
            // what broke the alignment: with `fixedSize` labels, 44 here put
            // the "Keep Awake" row's minimum width above the 145pt column, so
            // that row overflowed its own frame and took the overlay's trailing
            // edge with it. "Tasks ⌘J" is shorter and fitted, which is why only
            // one of the two moved.
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity,
               minHeight: Self.settingsRowHeight,
               maxHeight: Self.settingsRowHeight)
        // The switch is laid over the row's trailing edge rather than placed in
        // the flow, so where the label stops cannot move it.
        .overlay(alignment: .trailing) {
            // Tinted rather than left on the system accent, which painted it
            // the brightest object in a window that is otherwise greys and
            // terminal text.
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(theme.chrome.accent.color)
                // 36 is what the control measures; a smaller box would leave
                // it overflowing, and an overflowing child is placed by rules
                // that are not the alignment you asked for.
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 7)
        }
    }

    private var sleepHelp: String {
        if model.sleepGuard.isHolding {
            return "The display stays on while Ocarina is open, so a long build or an agent working is never cut short."
        }
        if model.sleepGuard.isEnabled {
            return "Requested, but the system has not granted it — the display may still sleep."
        }
        return "Off. The display sleeps on its usual schedule, even mid-run."
    }

    // MARK: - Rows

    /// Leaves the rename, keeping the old name when nothing was typed. Without
    /// this, clicking away from an empty field left the tab in a half-open edit
    /// that looked like nothing had happened.
    private func endRename(_ tab: TabItem, commit: Bool) {
        guard renamingTabID != nil else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit, !trimmed.isEmpty {
            model.rename(tab.id, to: trimmed)
        }
        renamingTabID = nil
        draftTitle = ""
    }

    /// Selects the existing name so typing replaces it. SwiftUI has no way to
    /// ask for this, so the field editor is asked directly once focus lands.
    private func selectAllInFieldEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }

    /// What the tab is running, when that is worth a picture. A shell at a
    /// prompt gets nothing: its symbol was a terminal, which is what every tab
    /// in this app is, and the slot it sat in is width the name can use. The
    /// activity dot stays a separate element beside it — badged onto the icon
    /// it read as a smudge, and colour on its own is the signal.
    @ViewBuilder
    private func tabIcon(for tab: TabItem) -> some View {
        if let look = TabIcon.meaningfulLook(for: tab.processName) {
            // The tint is a slot, not a colour: `TabIcon` says *which* of the
            // theme's colours, and the theme says what that is. See
            // `TabIcon.Tint`.
            let colour = look.tint == .agent
                ? theme.chrome.accent.color
                : theme.chrome.textTertiary.color

            Group {
                if let mark = look.mark {
                    // An agent wears its own mark, the same one it wears on the
                    // landing screen — drawn a touch smaller than the symbols
                    // beside it, because a filled shape at 11pt reads heavier
                    // than an SF Symbol at 11pt.
                    mark.filled(with: colour).frame(width: 10, height: 10)
                } else {
                    Image(systemName: look.symbol)
                        .font(theme.uiFont(11, weight: .medium))
                        .foregroundStyle(colour)
                }
            }
            .frame(width: 14, height: 14)
        }
    }

    private func closeButton(for tab: TabItem) -> some View {
        Button {
            model.closeTab(tab.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Self.badgeGlyph, weight: .bold))
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .background { Circle().fill(theme.chrome.border.color.opacity(0.18)) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.chrome.textPrimary.color)
        // The click is taken by the overlay rather than the button: it sits
        // above SwiftUI, so the row's select/rename taps cannot swallow it.
        .toolTip("Close this tab (⌘W)", in: Self.space, target: $toolTip) {
            model.closeTab(tab.id)
        }
    }

    /// The row's outline. Renaming owns the edge outright — it is a mode, and
    /// the accent border is the only thing saying so. Otherwise selection is
    /// brightest, hover is quieter but unmistakably present, and a row at rest
    /// has no edge at all so the column stays a list rather than a grid.
    private func rowStroke(isSelected: Bool, isHovered: Bool, isRenaming: Bool) -> Color {
        if isRenaming { return theme.chrome.accent.color }
        // The selected row wears the theme's accent. It was a white-ish border
        // at 16% over a white-ish wash at 12%, which is the same faint grey
        // edge in all fourteen themes — the one row you look at most, saying
        // nothing about which theme you are in.
        if isSelected { return theme.chrome.accent.color.opacity(0.34) }
        if isHovered { return theme.chrome.border.color.opacity(0.12) }
        return .clear
    }

    @ViewBuilder
    private func row(for tab: TabItem) -> some View {
        let isSelected = tab.id == model.selectedTabID
        let isHovered = tab.id == hoveredTabID
        let isRenaming = renamingTabID == tab.id

        HStack(spacing: 7) {
            // First in the row, so the whole column of dots can be read down
            // the edge without stopping at any of the names.
            StatusDot(activity: tab.activity)
            tabIcon(for: tab)

            if isRenaming {
                TextField("Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(theme.uiFont(12, weight: .medium))
                    .focused($isRenameFocused)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.terminal.background.color)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(theme.chrome.accent.color, lineWidth: 1)
                            }
                    }
                    .onSubmit { endRename(tab, commit: true) }
                    .onExitCommand { endRename(tab, commit: false) }
                    .onChange(of: isRenameFocused) { _, focused in
                        // Kept as the keyboard path — tabbing out of the field
                        // does move SwiftUI's focus. It is not the one that
                        // fires when you click away; see below.
                        if !focused { endRename(tab, commit: true) }
                    }
                    .commitOnClickOutside { endRename(tab, commit: true) }
                    .onAppear {
                        // The terminal's view owns the window's first
                        // responder, and SwiftUI's focus does not take it
                        // away on its own: the field appeared focused — it
                        // draws its own accent border — while every keystroke
                        // carried on into the shell, so a rename silently ran
                        // the new name as a command. Dropping the responder
                        // first leaves the chain empty for FocusState to land.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        DispatchQueue.main.async {
                            isRenameFocused = true
                            selectAllInFieldEditor()
                        }
                    }
            } else {
                // The name, and only the name.
                //
                // Hovering used to bring a second line — "Claude Code ·
                // ~/Ocarina-Terminal" — under it. Two things were wrong with
                // it: the row grew a second line of type at the exact moment
                // the pointer was moving through the column, which is the
                // worst possible moment to change what a row looks like; and
                // it answered a question nobody was asking, since the tab is
                // named for the work and the directory is a click away. It is
                // still on the tooltip for when it is genuinely wanted.
                Text(tab.title.ellipsised(to: TabSidebarView.titleLimit))
                    .font(theme.uiFont(12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // `layoutPriority(1)` would be the wrong way round: the
                    // name is the part that gives, and the badge beside it is
                    // 18pt whatever happens. Zero priority and a flexible
                    // frame is what makes the truncation land on the name
                    // rather than on the row's width.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                // One slot, one glyph: the close button, and only while the
                // pointer is on the row.
                //
                // There was a pin here too, marking a tab you had renamed by
                // hand, and the slot swapped between the two. It went for the
                // simplest reason — a badge has to earn the corner it sits in,
                // and this one was reporting a fact about the tab's *history*
                // rather than offering anything you could do. What it mostly
                // achieved was an icon that changed under the pointer.
                //
                // Not animated, unlike the rest of the row: the row's hover
                // animation crossfades, and a crossfade in a `ZStack` draws
                // both states at once.
                ZStack {
                    if isHovered { closeButton(for: tab) }
                }
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .animation(nil, value: isHovered)
            }
        }
        .padding(.horizontal, 7)
        // `maxWidth: .infinity`, like every other row in this column. With
        // only a minimum height the row took its *content's* width, so a name
        // that did not compress grew the row — and the pill behind it — past
        // the panel's own edge and out over the terminal. The column is 165pt
        // whatever the names in it are.
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        // Nothing in the row draws outside the pill. Belt to the frame's
        // braces: a name is one thing that can overrun a row, and whatever is
        // added to this row next does not get to rediscover that.
        //
        // Above the background rather than below it, or the clip would take
        // the outer half of the row's own 1pt stroke with it — and the 1.5pt
        // accent edge that says a row is being renamed would come out thinner
        // than the thing it is meant to stand out from.
        .clipShape(RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous))
        .background {
            // Milled out of the same metal rather than a pane laid over it:
            // material here caught the light the panel no longer does.
            //
            // Every state has to carry against a panel that is already
            // near-black. Hover was a 0.05 white wash and no border at all:
            // over metal this dark that is worth about two levels out of 255,
            // so a hovered row read as no row — the pointer was on something
            // and nothing came back. It gets a real edge now. The fill warms
            // the row, the stroke is what actually draws the container, and
            // selection stays a clear step above hover on both.
            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                .fill(isSelected ? theme.chrome.accent.color.opacity(0.11)
                                 : theme.chrome.rowHover.color.opacity(isHovered ? 0.07 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                        .stroke(rowStroke(isSelected: isSelected,
                                          isHovered: isHovered,
                                          isRenaming: isRenaming),
                                lineWidth: isRenaming ? 1.5 : 1)
                }
        }
        // The pointer crossing a row should look like the row lighting up,
        // rather than a state that swaps in whole between two frames.
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .contentShape(.rect)
        .help(tab.subtitle ?? tab.title)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            draftTitle = tab.title
            renamingTabID = tab.id
        })
        .simultaneousGesture(TapGesture().onEnded { model.selectTab(tab.id) })
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
        .contextMenu {
            Button("Rename…") {
                draftTitle = tab.title
                renamingTabID = tab.id
            }
            if tab.isManuallyNamed {
                Button("Resume Automatic Naming") {
                    model.resumeAutomaticNaming(for: tab.id)
                }
            }
            Divider()
            Button("Close Tab") { model.closeTab(tab.id) }
        }
    }
}

extension String {
    /// Cut to `limit` characters with an ellipsis, counting the ellipsis
    /// itself, so no title ever renders wider than the cap allows.
    func ellipsised(to limit: Int) -> String {
        guard count > limit, limit > 1 else { return self }
        let kept = prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return kept + "\u{2026}"
    }
}
