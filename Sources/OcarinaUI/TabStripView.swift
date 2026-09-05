import AppKit
import SwiftUI

/// The tab strip. The contextual task is the title; the process is secondary,
/// surfaced on hover rather than competing with it. A dot on the left carries
/// activity, so busy and failed tabs are findable without reading any text.
struct TabStripView: View {
    /// One long name should not be allowed to push the strip around, so the
    /// title is capped for display. The tab keeps its full name for renaming,
    /// the hover subtitle and the command palette.
    static let titleLimit = 24

    @Bindable var model: OcarinaModel
    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var draftTitle: String = ""
    @FocusState private var isRenameFocused: Bool
    @State private var toolTip: ToolTipTarget?

    private static let space = "tabstrip"

    var body: some View {
        VStack(spacing: 0) {
            // The hairline sits flush under the titlebar, with the air below it
            // instead of above. Padding here reads as extra titlebar — it is the
            // same colour — and pushed the window title off the centre of the
            // band the eye actually sees, since AppKit centres that title in the
            // 31.5pt titlebar alone.
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            strip
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

    private var strip: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(model.tabs) { tab in
                        chip(for: tab)
                    }
                    // Beside the last tab rather than across the window: it is
                    // where the pointer already is once you have closed a tab.
                    newTabButton
                }
                .padding(.horizontal, 10)
                // Asymmetric on purpose. The hairline above needs a little air
                // under it, but below the chips the terminal should start close
                // — 7pt each side plus a divider left the strip floating.
                .padding(.top, 7)
                .padding(.bottom, 5)
            }

            sleepToggle
                .padding(.trailing, 10)
        }
        .frame(height: 50)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var newTabButton: some View {
        Button {
            model.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                // Square, at the chip's own height and corner radius, so it
                // sits in the row of tabs rather than beside it.
                .frame(width: 38, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .toolTip("New tab (⌘T)", in: Self.space, target: $toolTip) {
            model.newTab()
        }
    }

    /// Ocarina keeps the Mac awake while it is open. The cup says whether it
    /// currently is, so a machine that will not sleep is never a mystery.
    private var sleepToggle: some View {
        Button {
            model.sleepGuard.isEnabled.toggle()
        } label: {
            Image(systemName: model.sleepGuard.isHolding
                  ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.sleepGuard.isHolding ? .primary : .secondary)
                // Same size as the chip and the plus. At 26pt it was a small
                // target pinned to the window edge, which is why its tool tip
                // was so easy to miss.
                .frame(width: 38, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.ultraThinMaterial)
                        .opacity(model.sleepGuard.isHolding ? 0.75 : 0.3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .toolTip(model.sleepGuard.isHolding
                 ? "Keeping this Mac awake — click to allow sleep"
                 : "Sleep allowed — click to keep this Mac awake",
                 in: Self.space, target: $toolTip) {
            model.sleepGuard.isEnabled.toggle()
        }
    }

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

    /// What the tab is running. The activity dot stays a separate element
    /// beside it: badged onto the icon it read as a smudge, and colour on its
    /// own is the signal.
    private func tabIcon(for tab: TabItem) -> some View {
        let look = TabIcon.look(for: tab.processName)
        return Image(systemName: look.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(look.tint)
            .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private func chip(for tab: TabItem) -> some View {
        let isSelected = tab.id == model.selectedTabID
        let isHovered = tab.id == hoveredTabID
        let isRenaming = renamingTabID == tab.id

        HStack(spacing: 8) {
            tabIcon(for: tab)
            StatusDot(activity: tab.activity)

            if isRenaming {
                TextField("Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isRenameFocused)
                    // Flexible, not a fixed 140: at a fixed width the row grew
                    // past the chip and pushed the close button out of it.
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.35))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
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
                        isRenameFocused = true
                        selectAllInFieldEditor()
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if tab.isManuallyNamed {
                            // A pinned name is the user's, not ours.
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        Text(tab.title.ellipsised(to: TabStripView.titleLimit))
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }

                    // Secondary information appears only when asked for.
                    if isHovered, let subtitle = tab.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
            }

            Button {
                model.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background {
                        Circle().fill(.white.opacity(isHovered ? 0.12 : 0))
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovered || isSelected ? .primary : .secondary)
            .opacity(isHovered || isSelected ? 1 : 0.35)
            // The click is taken by the overlay rather than the button: it sits
            // above SwiftUI, so the chip's select/rename taps cannot swallow it.
            .toolTip("Close this tab (⌘W)", in: Self.space, target: $toolTip) {
                model.closeTab(tab.id)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(minWidth: 150, maxWidth: isRenaming ? 280 : 230, minHeight: 38, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? .ultraThinMaterial : .thinMaterial)
                .opacity(isSelected ? 1 : (isHovered ? 0.7 : 0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isRenaming ? Color.accentColor.opacity(0.7)
                                           : .white.opacity(isSelected ? 0.18 : 0.07),
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
