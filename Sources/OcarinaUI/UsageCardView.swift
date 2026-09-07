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
            ZStack {
                OcarinaWindowView.panelFill(theme, at: place)
                OcarinaWindowView.panelSheen(theme, at: place)
            }
        }
        .help(helpText)
    }

    /// The card with a window behind it.
    @ViewBuilder
    private func spent(_ usage: UsageWindow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("This window")
                .font(theme.uiFont(10.5, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
            Spacer(minLength: 4)
            Text(Self.compact(usage.tokens))
                .font(theme.uiFont(12.5, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)
            Text("tokens")
                .font(theme.uiFont(10, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
        }

        HStack(spacing: 8) {
            TickMeter(fraction: usage.elapsedFraction(at: now))
            // The countdown sits *on* the meter's row, because the meter is
            // the clock and not the tokens. A bar under a token count that
            // is filling with something else needs the thing it is actually
            // measuring standing next to it, or it reads as a quota — which
            // is the one thing this card cannot show.
            Text(countdown(to: usage.resetsAt))
                .font(theme.uiFont(10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.chrome.textSecondary.color)
                .fixedSize()
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
        // The word takes the whole row rather than sitting opposite a "This
        // window" label: there is no window, so labelling one is the wrong
        // sentence, and the board's alphabet needs the width to be read at
        // all. Sized like the landing screen's tagline — 1.9 on 0.85 — which
        // is what this is, in a smaller frame.
        DotMatrixText(
            text: "NO SPEND YET",
            cell: 1.9,
            gap: 0.85,
            lit: theme.board.litDim.color,
            unlit: theme.board.unlit.color,
            glow: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 8) {
            // Floor 0, unlike the live meter: there is no window running, so
            // the one lamp that would say "this has begun" would be a lie.
            TickMeter(fraction: 0, floor: 0)
            Text("not started")
                .font(theme.uiFont(10, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)
                .fixedSize()
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

/// A meter drawn as lamps on the board.
///
/// Two reasons, and the second is the better one.
///
/// A solid bar is read as a proportion of something continuous, which invites
/// exactly the reading this card must not invite — that the fill is an
/// allowance running down. Counted lamps read as counted units, and these are:
/// the five-hour window in fifteen-minute pieces, of which some have gone.
///
/// And the app already has an alphabet. The wordmark at the top of the sidebar
/// and the empty state are both dot matrix, drawn in `board.lit` and
/// `board.unlit`, on the argument that a departure board is the one piece of
/// pure identity Ocarina has. A meter is exactly what such a board is for.
/// Drawing it in that language costs nothing and makes the token card belong
/// to the app rather than to every dashboard tile ever shipped.
struct TickMeter: View {
    var fraction: Double
    /// The fewest lamps that may be lit while there is anything to measure.
    ///
    /// 1, not 0. A window that has just opened is a minute into five hours,
    /// which rounds to no lamps at all — and twenty dark lamps under a token
    /// figure is indistinguishable from a meter that has failed to read. One
    /// lamp is the honest floor: the window is open, and this is the least it
    /// can be. The empty card passes 0, because there it is not open.
    var floor: Int = 1
    @Environment(\.theme) private var theme

    /// Five hours in quarter-hours. Enough to see one go by; few enough that
    /// each lamp is still a lamp rather than a hairline.
    private static let count = 20
    /// Two rows, because one row of dots is a dotted line and two is a panel.
    private static let rows = 2
    private static let cell: CGFloat = 3
    private static let gap: CGFloat = 1.6

    /// Cold at the top of the window, warm at the end of it.
    ///
    /// One flat colour for twenty lamps was the board's own `lit` and read as
    /// a bar that happened to be made of dots — you could see how many were
    /// on, but not, at a glance, whereabouts in the window you were. A ramp
    /// laid across the whole meter fixes that without adding a number: the
    /// lamps you have are dim and cool near the start and run up through the
    /// board's lit colour to its highlight as the five hours go. All three
    /// are the theme's own board colours, so it warms in whatever palette is
    /// on rather than in a hard-coded green-to-red nobody chose.
    private var ramp: Gradient {
        Gradient(colors: [
            theme.board.litDim.color,
            theme.board.lit.color,
            theme.board.highlight.color,
        ])
    }

    var body: some View {
        let reading = min(max(fraction, 0), 1)
        let lit = max(
            reading > 0 ? floor : 0,
            Int((Double(Self.count) * reading).rounded())
        )
        Canvas { context, size in
            let pitch = Self.cell + Self.gap
            // Spread across whatever width the card gives it, so the lamps sit
            // on the card's own edges rather than on a grid of their own.
            let step = max((size.width - Self.cell) / CGFloat(Self.count - 1), pitch)
            var on = Path(), off = Path()
            for column in 0..<Self.count {
                for row in 0..<Self.rows {
                    let dot = Path(
                        roundedRect: CGRect(
                            x: CGFloat(column) * step,
                            y: CGFloat(row) * pitch,
                            width: Self.cell,
                            height: Self.cell
                        ),
                        cornerRadius: Self.cell * 0.3
                    )
                    if column < lit { on.addPath(dot) } else { off.addPath(dot) }
                }
            }
            context.fill(off, with: .color(theme.board.unlit.color))
            // Across the meter's full width, not the lit run's: a lamp's
            // colour has to mean the same thing at 3 lamps as it does at 18,
            // and a gradient rescaled to the fill would make the last lit
            // lamp the warmest one at every reading.
            let shading = GraphicsContext.Shading.linearGradient(
                ramp,
                startPoint: CGPoint(x: 0, y: size.height / 2),
                endPoint: CGPoint(x: size.width, y: size.height / 2)
            )
            // The bloom, the same as the board's: an LED behind a diffuser,
            // not a rectangle that happens to be coloured in. How much
            // diffuser is the theme's to say — Steel has none.
            let bloom = theme.shape.bloom
            if bloom > 0 {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: Self.cell * 0.7 * bloom))
                    layer.fill(on, with: shading)
                }
            }
            context.fill(on, with: shading)
        }
        .frame(height: CGFloat(Self.rows) * (Self.cell + Self.gap) - Self.gap)
    }
}
