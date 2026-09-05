import SwiftUI

/// The pull tab on the right edge that opens the task list.
///
/// Five shapes in. What each one got wrong is worth keeping, because the
/// constraints pull against each other:
///
/// - Drawn over the terminal with a hard fill, it read as a sticker.
/// - Flush to the window edge, it fought the scroller for the same strip.
/// - Given a column of its own, the column showed the raw window backdrop as a
///   grey band down the side — the very thing the theming work removed.
///
/// So it floats over the terminal, inset just past the scroller, on a
/// translucent plate rather than a slab: the theme shows through it, and a soft
/// shadow does the work the border used to. The grip says it pulls.
struct PanelHandle: View {
    @Environment(\.theme) private var theme
    @Bindable var model: OcarinaModel

    @State private var isHovered = false

    private static let width: CGFloat = 22
    private static let height: CGFloat = 116

    private var isLit: Bool { isHovered || model.isTaskPanelVisible }

    var body: some View {
        Button {
            model.setTaskPanel(visible: !model.isTaskPanelVisible)
        } label: {
            VStack(spacing: 9) {
                Text("TASKS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.3)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(height: 46)

                grip
            }
            .foregroundStyle(isLit
                             ? theme.chrome.textPrimary.color
                             : theme.chrome.textSecondary.color)
            .frame(width: Self.width, height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.chrome.panelTop.color.opacity(isLit ? 0.92 : 0.68))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(theme.chrome.border.color.opacity(isLit ? 0.20 : 0.10),
                                    lineWidth: 1)
                    }
                    // Floating, so it casts. This is what replaces the hard
                    // edge the slab version needed to look attached.
                    .shadow(color: .black.opacity(isLit ? 0.45 : 0.3),
                            radius: isLit ? 9 : 6, x: -1, y: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isLit)
        .help(model.isTaskPanelVisible ? "Hide tasks (⌘J)" : "Show tasks (⌘J)")
    }

    /// Two columns of dots: the mark every draggable thing on a desktop wears,
    /// so the tab does not have to be discovered by accident.
    private var grip: some View {
        HStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(theme.chrome.textTertiary.color.opacity(isLit ? 0.9 : 0.6))
                            .frame(width: 2, height: 2)
                    }
                }
            }
        }
    }
}
