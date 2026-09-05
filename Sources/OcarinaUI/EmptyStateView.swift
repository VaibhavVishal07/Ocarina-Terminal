import SwiftUI

/// Shown when every tab has been closed.
///
/// The board look of an airport display, kept for the dot matrix and the way
/// unlit cells stay visible behind the words — but carrying only what is
/// actually true on this screen. A departures board's furniture (a clock, gate
/// numbers, an ON TIME column) says nothing here, so none of it is drawn.
///
/// With no tabs there is no strip either, so this owns the whole window.
struct EmptyStateView: View {
    let onNewTab: () -> Void

    @State private var isHovered = false

    // The board is the app's one piece of pure identity, so it is themed
    // rather than fixed: a Sakura board is pink dots on pale, an Ocarina board
    // is the blue it always was, and both come from the same five slots.
    @Environment(\.theme) private var theme

    private var backdrop: Color { theme.board.backdrop.color }
    private var unlit: Color { theme.board.unlit.color }
    private var lit: Color { theme.board.lit.color }
    private var litDim: Color { theme.board.litDim.color }
    private var amber: Color { theme.board.highlight.color }

    /// What you can actually do with no tabs open. Quick Actions leads,
    /// because this screen is where a new user is sitting and "how do I install
    /// anything" is the question they have.
    private static let hints = [
        ("CMD K", "QUICK ACTIONS"),
        ("CMD SHIFT P", "COMMAND PALETTE"),
        ("CMD Q", "QUIT"),
    ]

    var body: some View {
        ZStack {
            backdrop.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 0) {
                DotMatrixText(
                    text: "OCARINA",
                    cell: 4.4,
                    gap: 1.6,
                    lit: lit,
                    unlit: unlit
                )

                DotMatrixText(
                    text: "SONG OF A NEW TERMINAL",
                    cell: 1.9,
                    gap: 0.85,
                    lit: litDim,
                    unlit: unlit,
                    glow: false
                )
                .padding(.top, 12)

                callToAction
                    .padding(.top, 40)

                VStack(spacing: 9) {
                    ForEach(Self.hints, id: \.0) { keys, action in
                        DotMatrixText(
                            text: keys.column(13) + action.column(15),
                            cell: 1.9,
                            gap: 0.85,
                            lit: litDim,
                            unlit: unlit,
                            glow: false
                        )
                    }
                }
                .padding(.top, 34)
            }
        }
    }

    /// The one thing there is to do here, drawn as a lit row you can press.
    private var callToAction: some View {
        HStack(spacing: 40) {
            DotMatrixText(
                text: "NEW TERMINAL",
                cell: 2.9,
                gap: 1.15,
                lit: isHovered ? amber : lit,
                unlit: unlit
            )
            DotMatrixText(
                text: "CMD T",
                cell: 2.9,
                gap: 1.15,
                lit: isHovered ? amber.opacity(0.7) : litDim,
                unlit: unlit,
                glow: false
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 0.55 : 0.3)
        }
        .overlay {
            Rectangle()
                .stroke(isHovered ? amber : litDim, lineWidth: 1)
        }
        .contentShape(.rect)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onNewTab)
    }
}
