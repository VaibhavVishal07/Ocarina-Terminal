import SwiftUI

/// The tab strip. The contextual task is the title; the process is secondary,
/// surfaced on hover rather than competing with it. A dot on the left carries
/// activity, so busy and failed tabs are findable without reading any text.
struct TabStripView: View {
    @Bindable var model: OcarinaModel
    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var draftTitle: String = ""

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(model.tabs) { tab in
                        chip(for: tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }

            sleepToggle

            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.white.opacity(0.06))
                    }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help("New tab (⌘T)")
        }
        .frame(height: 52)
        .background(.black.opacity(0.28))
    }

    /// Ocarina keeps the Mac awake while it is open. The cup says whether it
    /// currently is, so a machine that will not sleep is never a mystery.
    private var sleepToggle: some View {
        Button {
            model.sleepGuard.isEnabled.toggle()
        } label: {
            Image(systemName: model.sleepGuard.isHolding
                  ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.sleepGuard.isHolding ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(model.sleepGuard.isHolding ? 0.06 : 0))
                }
        }
        .buttonStyle(.plain)
        .help(model.sleepGuard.isHolding
              ? "Keeping this Mac awake — click to allow sleep"
              : "Sleep allowed — click to keep this Mac awake")
    }

    @ViewBuilder
    private func chip(for tab: TabItem) -> some View {
        let isSelected = tab.id == model.selectedTabID
        let isHovered = tab.id == hoveredTabID

        HStack(spacing: 9) {
            StatusDot(activity: tab.activity)

            if renamingTabID == tab.id {
                TextField("Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 140)
                    .onSubmit {
                        model.rename(tab.id, to: draftTitle)
                        renamingTabID = nil
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
                        Text(tab.title)
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
            }

            Spacer(minLength: 4)

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
            .help("Close tab (⌘W)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(minWidth: 150, maxWidth: 230, minHeight: 38, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? .white.opacity(0.14) : .white.opacity(isHovered ? 0.07 : 0.03))
        }
        .contentShape(.rect)
        .help(tab.subtitle ?? tab.title)
        .onTapGesture { model.selectTab(tab.id) }
        .onTapGesture(count: 2) {
            draftTitle = tab.title
            renamingTabID = tab.id
        }
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
