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
        .toolTip("New tab — opens another terminal in this window (⌘T)") {
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.sleepGuard.isHolding ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.ultraThinMaterial)
                        .opacity(model.sleepGuard.isHolding ? 0.75 : 0.3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .toolTip(model.sleepGuard.isHolding
                 ? "Keeping this Mac awake so it will not sleep while Ocarina is open. Click to allow sleep."
                 : "This Mac can sleep normally. Click to keep it awake while Ocarina is open.") {
            model.sleepGuard.isEnabled.toggle()
        }
    }

    /// The app mark, trimmed of its plate and clipped to the same corner the
    /// chip uses. The activity dot stays a separate element beside it: badged
    /// onto the icon it read as a smudge, and colour on its own is the signal.
    private var tabIcon: some View {
        Group {
            if let mark = OcarinaIcon.mark {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.10))
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func chip(for tab: TabItem) -> some View {
        let isSelected = tab.id == model.selectedTabID
        let isHovered = tab.id == hoveredTabID

        HStack(spacing: 8) {
            tabIcon
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
            // The click is taken by the overlay rather than the button: it sits
            // above SwiftUI, so the chip's select/rename taps cannot swallow it.
            .toolTip("Close this tab (⌘W)") {
                model.closeTab(tab.id)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(minWidth: 150, maxWidth: 230, minHeight: 38, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? .ultraThinMaterial : .thinMaterial)
                .opacity(isSelected ? 1 : (isHovered ? 0.7 : 0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(isSelected ? 0.18 : 0.07), lineWidth: 1)
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
