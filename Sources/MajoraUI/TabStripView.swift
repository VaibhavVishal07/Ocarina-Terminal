import SwiftUI

/// The tab strip. The contextual task is the title; the process is secondary,
/// surfaced on hover rather than competing with it.
struct TabStripView: View {
    @Bindable var model: MajoraModel
    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var draftTitle: String = ""

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tabs) { tab in
                        chip(for: tab)
                    }
                }
                .padding(.horizontal, 10)
            }

            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help("New tab (⌘T)")
        }
        .frame(height: 38)
        .background(.black.opacity(0.28))
    }

    @ViewBuilder
    private func chip(for tab: TabItem) -> some View {
        let isSelected = tab.id == model.selectedTabID
        let isHovered = tab.id == hoveredTabID

        HStack(spacing: 6) {
            if tab.isManuallyNamed {
                // A pinned name is the user's, not ours.
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }

            if renamingTabID == tab.id {
                TextField("Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 130)
                    .onSubmit {
                        model.rename(tab.id, to: draftTitle)
                        renamingTabID = nil
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)

                    // Secondary information appears only when asked for.
                    if isHovered, let subtitle = tab.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if isHovered || isSelected {
                Button {
                    model.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 110, maxWidth: 200, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
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
