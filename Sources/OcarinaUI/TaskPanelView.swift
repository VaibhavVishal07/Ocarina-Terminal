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

    static let width: CGFloat = 230

    /// The breathing room below the titlebar, matching the gap the sidebar
    /// leaves above its first tab so the two columns start on the same line.
    private static let inset: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(theme.chrome.border.color.opacity(0.12)).frame(height: 1)

            if tasks.isEmpty { empty } else { list }
        }
        .frame(width: Self.width)
        .background {
            ZStack {
                theme.chrome.panelTop.color
                if let pattern = theme.pattern {
                    PatternView(motif: pattern)
                }
            }
            // Under the titlebar as well, or the panel stops short of it and
            // leaves the raw window backdrop showing in the corner.
            .ignoresSafeArea(edges: .top)
        }
    }

    /// No dismiss control: the panel is part of the window now, like the
    /// sidebar. The count is the whole header.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Tasks")
                .font(theme.uiFont(11.5, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)
            if !tasks.isEmpty {
                Text("\(tasks.filter { $0.state == .finished }.count)/\(tasks.count)")
                    .font(theme.uiFont(10.5))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        // 40 here was clearing the titlebar a second time — the window's safe
        // area already does it, which is what the sidebar relies on. It left the
        // header stranded a third of the way down an otherwise empty column.
        .padding(.top, Self.inset)
        .padding(.bottom, Self.inset)
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
                .font(theme.uiFont(11.5, weight: .semibold))
                .foregroundStyle(theme.chrome.textSecondary.color)

            Text("Ask the agent in this tab for something and it appears here.")
                .font(theme.uiFont(11))
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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
            Text(task.title)
                .font(theme.uiFont(11))
                .foregroundStyle(finished
                                 ? theme.chrome.textSecondary.color
                                 : theme.chrome.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .help(task.prompt)
    }
}
