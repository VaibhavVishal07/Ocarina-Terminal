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

    // Shared with the rest of the app, so the switch in the sidebar and the
    // board here cannot drift apart.
    private static let backdrop = Palette.backdrop
    private static let unlit = Palette.unlit
    private static let lit = Palette.lit
    private static let litDim = Palette.litDim
    private static let amber = Palette.amber

    /// Only the two things you can actually do with no tabs open. Closing a tab
    /// and jumping between terminals both need a terminal to exist.
    private static let hints = [("CMD SHIFT P", "COMMAND PALETTE"), ("CMD Q", "QUIT")]

    var body: some View {
        ZStack {
            Self.backdrop.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 0) {
                DotMatrixText(
                    text: "OCARINA",
                    cell: 4.4,
                    gap: 1.6,
                    lit: Self.lit,
                    unlit: Self.unlit
                )

                DotMatrixText(
                    text: "SONG OF A NEW TERMINAL",
                    cell: 1.9,
                    gap: 0.85,
                    lit: Self.litDim,
                    unlit: Self.unlit,
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
                            lit: Self.litDim,
                            unlit: Self.unlit,
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
                lit: isHovered ? Self.amber : Self.lit,
                unlit: Self.unlit
            )
            DotMatrixText(
                text: "CMD T",
                cell: 2.9,
                gap: 1.15,
                lit: isHovered ? Self.amber.opacity(0.7) : Self.litDim,
                unlit: Self.unlit,
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
                .stroke(isHovered ? Self.amber : Self.litDim, lineWidth: 1)
        }
        .contentShape(.rect)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onNewTab)
    }
}
