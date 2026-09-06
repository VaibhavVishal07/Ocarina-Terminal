import OcarinaTerminalContext
import SwiftUI

/// Tasks: what you have asked the agent in this tab.
///
/// The problem it solves is losing track: you give an agent five things across
/// twenty minutes and cannot remember which of them it actually got to. The
/// list is read from the transcript the agent writes anyway, so it costs the
/// session nothing and survives scrollback.
struct TaskPanelView: View {
    @Environment(\.theme) private var theme
    let tasks: [AgentTask]
    let clear: () -> Void

    @State private var isClearHovered = false

    /// The shared side-panel width — this column and the sidebar are the same
    /// width, because they are the same kind of object.
    static let width: CGFloat = OcarinaWindowView.panelWidth

    /// The breathing room below the titlebar, matching the gap the sidebar
    /// leaves above its first tab so the two columns start on the same line.
    private static let inset: CGFloat = 10

    /// The gap between the panel's edge and the words in it.
    ///
    /// The list sat 8 from the top and 8 from the left, inside a card that is
    /// itself flush against the window's gutter, and the text read as pressed
    /// into the corner. This is the one number for all four sides of it, so
    /// the header and the list cannot drift apart.
    private static let textInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(theme.chrome.border.color.opacity(0.12)).frame(height: 1)

            if tasks.isEmpty { empty } else { list }
        }
        .frame(width: Self.width)
        // The top of the right-hand column, so it carries the light and the
        // token card below it carries the fall.
        .background {
            ZStack {
                OcarinaWindowView.panelFill(theme, at: .top)
                OcarinaWindowView.panelSheen(theme, at: .top)
            }
        }
    }

    /// No dismiss control: the panel is part of the window now, like the
    /// sidebar. The count is the whole header.
    private var header: some View {
        HStack(spacing: 6) {
            // Bigger than the rows under it, and only it. The whole panel was
            // scaled to 16 when the heading was the only part that wanted to
            // be — which left every task set larger than "New Tab" and "Theme"
            // in the sidebar beside it, so the two columns read as two apps.
            Text("Tasks")
                .font(theme.uiFont(14, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)
            if !tasks.isEmpty {
                Text("\(tasks.filter { $0.state == .finished }.count)/\(tasks.count)")
                    .font(theme.uiFont(11))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            Spacer(minLength: 4)

            // Only when there is something to clear, and only on hover: a
            // permanently lit "clear" over a list you are reading is an
            // invitation to lose it by accident.
            if !tasks.isEmpty {
                // The word, not a control drawn around it.
                //
                // It was an eraser glyph, which is an icon button — a thing
                // with a shape, sitting in a corner, asking to be pressed. The
                // panel is a list you read; the one action on it should be a
                // quiet marker you can find when you want it and not notice
                // when you do not. Text at tertiary weight that comes up to
                // full on hover is that, and it also says what it does, which
                // a picture of an eraser never quite did.
                Button(action: clear) {
                    Text("Clear")
                        .font(theme.uiFont(11, weight: .medium))
                        .foregroundStyle(isClearHovered
                                         ? theme.chrome.textPrimary.color
                                         : theme.chrome.textTertiary.color)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { isClearHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isClearHovered)
                .help("Clear this list. The agent's own history is not touched.")
            }
        }
        .padding(.horizontal, Self.textInset)
        // 40 here was clearing the titlebar a second time — the window's safe
        // area already does it, which is what the sidebar relies on. It left the
        // header stranded a third of the way down an otherwise empty column.
        .padding(.vertical, Self.textInset)
    }

    /// Says what it is waiting for, in the middle of the space it will fill.
    ///
    /// A single line in the top corner read as a panel that had failed to load
    /// something. Centred, with the mark above it, the emptiness looks
    /// deliberate — this is a list with nothing in it yet, not a broken one.
    private var empty: some View {
        VStack(spacing: 9) {
            Image(systemName: "checklist")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(theme.chrome.textTertiary.color.opacity(0.65))

            Text("No tasks yet")
                .font(theme.uiFont(14, weight: .semibold))
                .foregroundStyle(theme.chrome.textSecondary.color)

            Text("Ask the agent in this tab for something and it appears here.")
                .font(theme.uiFont(11.5))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(tasks.reversed()) { task in
                    row(task)
                }
            }
            .padding(.horizontal, Self.textInset)
            .padding(.vertical, Self.textInset)
        }
    }

    private func row(_ task: AgentTask) -> some View {
        let finished = task.state == .finished
        return HStack(alignment: .top, spacing: 8) {
            // A green tick pulls the eye to the things already dealt with,
            // which is the opposite of what a to-do list is for: the one row
            // that matters is the unfinished one. So the tick is quiet, and
            // the open item is an empty box waiting to be filled.
            Image(systemName: finished ? "checkmark" : "square")
                .font(.system(size: finished ? 10 : 10.5,
                              weight: finished ? .semibold : .regular))
                .foregroundStyle(finished
                                 ? theme.chrome.textSecondary.color
                                 : theme.chrome.textTertiary.color)
                .frame(width: 12, alignment: .center)
                .padding(.top, 2)

            // No strikethrough. A line through eleven-point text is a line
            // through the middle of every lowercase letter, and the row stops
            // being readable at exactly the moment it becomes reference
            // material. The tick and the dimmer colour already say "finished".
            // The same size the sidebar sets a tab name and "New Tab" in.
            // At 11 the two columns looked like different apps.
            Text(task.title)
                .font(theme.uiFont(12))
                .foregroundStyle(finished
                                 ? theme.chrome.textSecondary.color
                                 : theme.chrome.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .help(task.prompt)
    }
}
