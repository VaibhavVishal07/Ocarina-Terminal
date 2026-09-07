import SwiftUI

/// The row of tools under the wordmark on the landing screen.
///
/// An icon, a word, and what pressing it will do. That is the whole thing, and
/// the restraint is the point: this screen had a heading, a row of dot-matrix
/// plates, a caption explaining the plates, a lit slab, and three rows of
/// shortcuts, and a person landing on it could not tell which of the five was
/// the thing to press.
///
/// So there is one row of targets, and everything else on the screen is either
/// the mark at the top or a quiet line at the bottom. The tools already
/// installed come first, because on every launch after the first the thing
/// somebody is reaching for is the one they already have.
struct AgentDock: View {
    @Environment(\.theme) private var theme

    /// Which tools are here, resolved by whoever owns the screen so this view
    /// never touches the file system while it lays itself out.
    let installed: Set<String>
    let onPick: (AgentTool) -> Void
    let onMore: () -> Void

    @State private var hovered: String?

    private static let moreID = "more"
    /// Big enough to be the obvious target on an otherwise empty screen, and
    /// no bigger: four of these plus the wordmark is the whole composition.
    private static let tile: CGFloat = 62
    private static let mark: CGFloat = 25
    private static let corner: CGFloat = 17
    private static let gap: CGFloat = 18

    private var lit: Color { theme.board.lit.color }
    private var litDim: Color { theme.board.litDim.color }
    private var amber: Color { theme.board.highlight.color }

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(AgentCatalog.ordered(byInstalled: installed)) { tool in
                let isInstalled = installed.contains(tool.id)
                item(
                    id: tool.id,
                    mark: tool.mark,
                    label: tool.label,
                    // The two words that matter. Everything else on this screen
                    // can be worked out by looking; whether pressing this
                    // downloads something cannot.
                    action: isInstalled ? "Open" : "Install",
                    isInstalled: isInstalled,
                    hint: tool.blurb,
                    name: tool.name,
                    onPress: { onPick(tool) }
                )
            }

            // Node, Git, Homebrew, and any agent that arrives after this
            // version shipped. A dock of three with no way past it is a dock
            // that goes out of date the week something else appears.
            item(
                id: Self.moreID,
                mark: .plus,
                label: "More",
                action: "Browse",
                isInstalled: false,
                hint: "Everything else Ocarina can install for you.",
                name: "More tools",
                onPress: onMore
            )
        }
    }

    /// The icon in its box.
    ///
    /// Split out from `item` because the two of them together are more than
    /// the type checker will sit through in one expression.
    private func square(
        mark: AgentMark,
        face: Color,
        isInstalled: Bool,
        isHovered: Bool
    ) -> some View {
        // Dashed while it is not here yet. A missing tool needs to look like an
        // outline waiting to be filled rather than like a tool that is present
        // but switched off, and dimming alone reads as the second thing.
        let edge: Color = isHovered ? amber : (isInstalled ? lit.opacity(0.55) : litDim.opacity(0.5))
        let dash: [CGFloat] = isInstalled ? [] : [3, 3]
        let box = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)

        return mark.filled(with: face)
            .frame(width: Self.mark, height: Self.mark)
            .frame(width: Self.tile, height: Self.tile)
            .background { box.fill(.ultraThinMaterial).opacity(isHovered ? 0.7 : 0.38) }
            .overlay { box.strokeBorder(edge, style: StrokeStyle(lineWidth: 1, dash: dash)) }
            // A press should feel like the icon moved, not like a rectangle
            // somewhere changed colour.
            .scaleEffect(isHovered ? 1.05 : 1)
    }

    private func item(
        id: String,
        mark: AgentMark,
        label: String,
        action: String,
        isInstalled: Bool,
        hint: String,
        name: String,
        onPress: @escaping () -> Void
    ) -> some View {
        let isHovered = hovered == id
        let face = isHovered ? amber : (isInstalled ? lit : litDim)

        return VStack(spacing: 9) {
            square(mark: mark, face: face, isInstalled: isInstalled, isHovered: isHovered)

            VStack(spacing: 2) {
                Text(label)
                    .font(theme.uiFont(12.5, weight: .semibold))
                    .foregroundStyle(isInstalled ? theme.chrome.textPrimary.color
                                                 : theme.chrome.textSecondary.color)
                Text(action)
                    .font(theme.uiFont(10.5, weight: .medium))
                    .foregroundStyle(isHovered ? amber : theme.chrome.textTertiary.color)
            }
        }
        .frame(width: Self.tile)
        .contentShape(.rect)
        .onHover { inside in
            if inside { hovered = id }
            // Only clears its own: two icons this close can report the entry to
            // the next before the exit from this one, and an unconditional nil
            // there leaves the row with nothing hovered mid-sweep.
            else if hovered == id { hovered = nil }
        }
        .onTapGesture(perform: onPress)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(name)
        .accessibilityValue(isInstalled ? "Installed" : "Not installed")
        .accessibilityHint("\(hint) \(isInstalled ? "Opens it in a new tab." : "Runs the install in a new tab.")")
    }
}
