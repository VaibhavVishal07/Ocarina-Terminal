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
    /// Narrow on purpose. A name that does not fit is truncated rather than
    /// given more room: the column is for picking a tab out of a list, and the
    /// terminal beside it is what the window is actually for.
    static let width: CGFloat = 165
    /// Only catches pathological names — the width truncates long ones long
    /// before this does.
    static let titleLimit = 34
    /// Both trailing glyphs — the pin and the close button — are drawn at this
    /// size, in a circle of this diameter, in the same slot. A pinned tab and
    /// a hovered one then have identical geometry and nothing shifts as they
    /// swap.
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
    private static let rowCorner: CGFloat = 12
    /// One height for everything in the list, tabs and the new-tab button
    /// alike. A row is a single line of 12pt text; at 48 it carried more empty
    /// space than text and stood apart from the rest of the column instead of
    /// belonging to it.
    private static let rowHeight: CGFloat = 38

    @Bindable var model: OcarinaModel
    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var draftTitle: String = ""
    @FocusState private var isRenameFocused: Bool
    @State private var toolTip: ToolTipTarget?

    private static let space = "tabsidebar"

    var body: some View {
        VStack(spacing: 0) {
            // The window's titlebar safe area already pushes the sidebar clear
            // of the traffic lights. This is the breathing room below them, not
            // the clearance itself — reserving the full height of the titlebar
            // here as well is what left the first tab stranded halfway down.
            Color.clear.frame(height: Self.inset)

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

            sleepPanel
        }
        .frame(width: Self.width)
        .background(metal)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        }
        .coordinateSpace(name: Self.space)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if let toolTip {
                    ToolTipBubble(target: toolTip, width: geometry.size.width)
                }
            }
        }
    }

    // MARK: - Surface

    /// Dark metal, not glass. Translucent material let whatever sat behind the
    /// window through, and the sheen over it made the column the brightest
    /// thing on a screen whose other half is a nearly black terminal. This is
    /// an opaque dark panel with one faint highlight along the top — enough to
    /// read as a brushed surface catching light, not enough to shine.
    private var metal: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.128, green: 0.133, blue: 0.143),
                    Color(red: 0.100, green: 0.104, blue: 0.112),
                    Color(red: 0.078, green: 0.081, blue: 0.088),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.white.opacity(0.035), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    // MARK: - New tab

    private var newTabButton: some View {
        Button {
            model.newTab()
        } label: {
            HStack(spacing: 7) {
                // The plus takes the status dot's column, so "New Tab" starts
                // on the same left edge as a plain shell tab's name.
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 9)
                Text("New Tab")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text("\u{2318}T")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(minHeight: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
    }

    // MARK: - Keep awake

    /// Ocarina holds the display awake while it is open, which is a thing a
    /// machine does silently and inexplicably unless something says so. The
    /// state gets one short line — at this width a paragraph became six
    /// wrapped lines that nobody reads twice.
    private var sleepPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
                .padding(.bottom, 6)

            HStack(spacing: 7) {
                Image(systemName: model.sleepGuard.isHolding
                      ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(model.sleepGuard.isHolding ? .primary : .secondary)
                    .frame(width: 15)

                Text("Keep awake")
                    .font(.system(size: 11.5, weight: .medium))

                Spacer(minLength: 2)

                // `sleepGuard` is a `let` on the model, so there is no
                // `$model.sleepGuard` to project; the guard is observable in
                // its own right, which is all the toggle needs.
                Toggle("", isOn: Binding(
                    get: { model.sleepGuard.isEnabled },
                    set: { model.sleepGuard.isEnabled = $0 }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Text(sleepExplanation)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Self.inset)
        .help(sleepHelp)
    }

    /// Short enough for one line at this width; the full sentence lives in the
    /// hover help, where there is room for it.
    private var sleepExplanation: String {
        if model.sleepGuard.isHolding { return "Display stays on." }
        if model.sleepGuard.isEnabled { return "Requested, not granted." }
        return "Sleeps as usual."
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
            Image(systemName: look.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(look.tint)
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
                .background { Circle().fill(.white.opacity(0.12)) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        // The click is taken by the overlay rather than the button: it sits
        // above SwiftUI, so the row's select/rename taps cannot swallow it.
        .toolTip("Close this tab (⌘W)", in: Self.space, target: $toolTip) {
            model.closeTab(tab.id)
        }
    }

    /// A pinned name is the user's, not ours. Same glyph size and same circle
    /// as the close button, in the same slot.
    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: Self.badgeGlyph, weight: .bold))
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            .background { Circle().fill(.white.opacity(0.08)) }
            .foregroundStyle(.secondary)
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
                    .font(.system(size: 12, weight: .medium))
                    .focused($isRenameFocused)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.black.opacity(0.35))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            }
                    }
                    .onSubmit { endRename(tab, commit: true) }
                    .onExitCommand { endRename(tab, commit: false) }
                    .onChange(of: isRenameFocused) { _, focused in
                        // Clicking away commits what was typed, and keeps the
                        // old name when nothing was.
                        if !focused { endRename(tab, commit: true) }
                    }
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title.ellipsised(to: TabSidebarView.titleLimit))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // Secondary information appears only when asked for.
                    if isHovered, let subtitle = tab.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // One slot, two glyphs: the pin while the row is at rest, the
                // close button while the pointer is on it. Hovering a pinned
                // tab is already the moment you are reaching for the cross.
                ZStack {
                    if isHovered {
                        closeButton(for: tab)
                    } else if tab.isManuallyNamed {
                        pinBadge
                    }
                }
                .frame(width: Self.badgeSize, height: Self.badgeSize)
            }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: Self.rowHeight, alignment: .leading)
        .background {
            // Milled out of the same metal rather than a pane laid over it:
            // material here caught the light the panel no longer does.
            RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.085 : (isHovered ? 0.05 : 0)))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous)
                        .stroke(isRenaming ? Color.accentColor.opacity(0.7)
                                           : .white.opacity(isSelected ? 0.13 : 0),
                                lineWidth: isRenaming ? 1.5 : 1)
                }
        }
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
