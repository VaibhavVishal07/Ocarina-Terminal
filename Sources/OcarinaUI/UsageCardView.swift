import OcarinaTerminalContext
import SwiftUI

/// The small card under the task panel: what this agent has spent, and how
/// long the window it is spending from has left to run.
///
/// It says *used*, not *left*, and that is not a hedge — see the note on
/// `TokenUsageSource`. Nothing on the machine records the size of the
/// allowance, and the only way to find out would be to spend the user's own
/// credentials on a request they did not make.
///
/// Two rows and a meter: 49pt against the 101 it was, both measured. It began
/// as a dashboard tile — an icon, a caption line, a 21pt number, a rule and a
/// sentence — which is a great deal of card for one figure you glance at on
/// your way past. A label with its value on the same line, and a meter under
/// it, is the shape this belongs in.
struct UsageCardView: View {
    @Environment(\.theme) private var theme
    /// Nil until something has been spent. A five-hour window only exists
    /// once there is a request in it, so the first minutes of a session have
    /// no window to report — and the card used to answer that by not being
    /// drawn, which left the panel beside the terminal ending in a blank.
    /// It has an empty state now; see `nothingYet`.
    let usage: UsageWindow?
    /// Passed in rather than read from the clock, so the countdown ticks with
    /// the view's own timer and the card is trivially previewable.
    let now: Date
    /// Where this card sits in its column, which decides how it is lit. See
    /// `OcarinaWindowView.panelFill`.
    var place: OcarinaWindowView.PanelPlace = .top

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let usage {
                spent(usage)
            } else {
                nothingYet
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            OcarinaWindowView.panelSurface(theme, at: place)
        }
        .help(helpText)
    }

    /// The card with a window behind it: what has been spent, and when the
    /// window comes back.
    ///
    /// ## Why there is no percentage
    ///
    /// A card like this wants to say *67% used* with a bar under it, the way
    /// every other usage meter does, and this one cannot. **Nothing on the
    /// machine records the size of the allowance.** The transcript Claude Code
    /// writes carries `message.usage` — input, output, cache — and no limit, no
    /// tier ceiling, no reset quota. `/usage` inside Claude Code asks the API
    /// live and never writes the answer down.
    ///
    /// Several denominators were tried here and all of them were inventions: a
    /// high-water mark of your own history, a plan you declare in a picker, a
    /// ratio against the clock. Each produced a confident number that looked
    /// like the one people wanted and was not it. **A wrapper does not get to
    /// make up the figure the thing it wraps declines to give.**
    ///
    /// So: what was spent, which is true, and when the window resets, which is
    /// also true. The meter measures the window's own five hours — time, not
    /// tokens — and the hairline says these are two readings rather than one
    /// sentence.
    @ViewBuilder
    private func spent(_ usage: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Self.compact(usage.tokens))
                    .font(theme.uiFont(17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.chrome.textPrimary.color)
                Text("tokens")
                    .font(theme.uiFont(10.5, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                Spacer(minLength: 4)
                Text(countdown(to: usage.resetsAt) + " left")
                    .font(theme.uiFont(10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }

            WindowBar(elapsed: usage.elapsedFraction(at: now))

            Rectangle()
                .fill(theme.chrome.border.color.opacity(0.14))
                .frame(height: 1)
                .padding(.vertical, 1)

            HStack(spacing: 8) {
                Text("Refreshes")
                    .font(theme.uiFont(10.5, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                Spacer(minLength: 4)
                // In the board's alphabet, which has the colon it needs — the
                // same hand the empty state and the menu bar are written in.
                DotMatrixText(
                    text: Self.clock.string(from: usage.resetsAt),
                    cell: 1.5,
                    gap: 0.7,
                    lit: theme.board.highlight.color,
                    unlit: theme.board.unlit.color,
                    glow: false
                )
            }
        }
    }

    /// The card with nothing behind it yet.
    ///
    /// Drawn rather than skipped, and drawn in the board's alphabet rather
    /// than in a sentence. An empty card has one job — to say that the zero
    /// is a reading and not a failure to read — and a row of unlit lamps
    /// under a lit word is the app already saying exactly that on its landing
    /// screen. A greyed-out "0 tokens" would be the other thing: a number
    /// nobody can tell apart from a meter that has broken.
    @ViewBuilder
    private var nothingYet: some View {
        // No dial here, and that is the point rather than an omission: there
        // is no window open, so a clock face with nothing on it would be a
        // reading of something that is not running. It also takes the width
        // back — the board's alphabet needs about 195pt to set "NO SPEND YET",
        // and a 56pt dial beside it clipped the last letter off the card.
        Group {
            VStack(alignment: .leading, spacing: 5) {
                // The board's alphabet rather than a sentence. An empty card
                // has one job — to say that the zero is a reading and not a
                // failure to read — and a row of unlit lamps under a lit word
                // is the app already saying exactly that on its landing
                // screen. A greyed-out "0 tokens" would be the other thing.
                DotMatrixText(
                    text: "NO SPEND YET",
                    cell: 1.9,
                    gap: 0.85,
                    lit: theme.board.litDim.color,
                    unlit: theme.board.unlit.color,
                    glow: false
                )
                Text("A window opens on this agent's first request.")
                    .font(theme.uiFont(10, weight: .medium))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func countdown(to resetsAt: Date) -> String {
        let seconds = max(0, resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return "ended" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var helpText: String {
        guard let usage else {
            return """
            Nothing has been spent yet, so there is no five-hour window to \
            report. One opens on this agent's first request.
            """
        }
        return """
        Tokens this agent has sent and received in the five-hour window that \
        opened at \(Self.clock.string(from: usage.startedAt)), which resets at \
        \(Self.clock.string(from: usage.resetsAt)). Ocarina cannot show how \
        much is left: nothing written to disk says how big the allowance is.
        """
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 1_432_000 -> "1.4M". A card this size cannot hold a grouped integer, and
    /// the exact figure is not what anybody reads it for.
    static func compact(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000:
            return "\(tokens)"
        case ..<1_000_000:
            let thousands = Double(tokens) / 1_000
            return thousands < 10
                ? String(format: "%.1fK", thousands)
                : "\(Int(thousands.rounded()))K"
        default:
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }
}

/// The five-hour window, running down.
///
/// It measures **time, not tokens** — how far through the window you are, which
/// is a thing the app actually knows. That distinction is the whole reason this
/// card has no percentage: see `UsageCardView.spent(_:)`.
///
/// ## The unlit half is not empty space
///
/// The meter this replaces drew its dark cells in `board.unlit`, which on most
/// themes is a shade off the panel itself — so a window that had just opened
/// read as one short bright bar floating in nothing, and you could not see how
/// much of the track was still to come. **The unspent track is the other half
/// of the reading.** It is drawn at a real weight: `litDim` held back, visible
/// on every theme in the set and still clearly the unlit state.
struct WindowBar: View {
    /// 0 at the top of the window, 1 at the end of it.
    var elapsed: Double
    /// The fewest cells that may be lit while a window is open.
    ///
    /// 1, not 0. A window a minute into five hours rounds to nothing lit, and
    /// an empty bar under a token figure is indistinguishable from a meter that
    /// has failed to read.
    var floor: Int = 1
    @Environment(\.theme) private var theme

    /// Five hours in quarter-hours.
    private static let count = 20
    private static let height: CGFloat = 7
    private static let gap: CGFloat = 2.2

    /// Cold at the top of the window, warm at the end of it — the board's own
    /// three colours, so it warms in whatever palette is on.
    private var ramp: Gradient {
        Gradient(colors: [
            theme.board.litDim.color,
            theme.board.lit.color,
            theme.board.highlight.color,
        ])
    }

    var body: some View {
        let reading = min(max(elapsed, 0), 1)
        let lit = max(
            reading > 0 ? floor : 0,
            Int((Double(Self.count) * reading).rounded())
        )
        Canvas { context, size in
            let step = (size.width + Self.gap) / CGFloat(Self.count)
            let width = max(1, step - Self.gap)
            var on = Path(), track = Path()
            for index in 0..<Self.count {
                let cell = Path(
                    roundedRect: CGRect(x: CGFloat(index) * step, y: 0,
                                        width: width, height: Self.height),
                    cornerRadius: Self.height * 0.28
                )
                if index < lit { on.addPath(cell) } else { track.addPath(cell) }
            }
            context.fill(track, with: .color(theme.board.litDim.color.opacity(0.34)))

            // Across the whole track rather than the lit run, so a cell's
            // colour means the same thing at four lit as it does at twenty.
            let shading = GraphicsContext.Shading.linearGradient(
                ramp,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            )
            let bloom = theme.shape.bloom
            if bloom > 0 {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: Self.height * 0.5 * bloom))
                    layer.fill(on, with: shading)
                }
            }
            context.fill(on, with: shading)
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("\(Int((reading * 100).rounded())) per cent through this window")
    }
}
