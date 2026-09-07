import OcarinaTerminalContext
import SwiftUI

/// The small card under the task panel: what the agent in this tab is doing
/// right now.
///
/// It replaced the token card, which answered a question — how much have I
/// spent — that you ask once an hour, in a slot you look at every few seconds.
/// The reading that belongs in a glance is whether the thing you asked for is
/// still going, and the tab's dot was carrying that on its own at nine points
/// across the window. That figure has not gone: it is in the menu bar, beside
/// the Wi-Fi, which is where a once-an-hour question belongs.
///
/// Three states and no fourth. Idle draws nothing at all — a card that says
/// "nothing is happening" is furniture, and the panel above it is already the
/// list of things that have.
struct StatusCardView: View {
    @Environment(\.theme) private var theme
    let activity: TabActivity
    /// What is being worked on, when anything is. Already summarised.
    let task: String?
    /// Where this card sits in its column, which decides how it is lit.
    var place: OcarinaWindowView.PanelPlace = .bottom

    var body: some View {
        HStack(spacing: 10) {
            mark
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(theme.uiFont(12.5, weight: .semibold))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                if let detail {
                    Text(detail)
                        .font(theme.uiFont(10.5, weight: .medium))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                OcarinaWindowView.panelFill(theme, at: place)
                OcarinaWindowView.panelSheen(theme, at: place)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(headline): \($0)" } ?? headline)
    }

    @ViewBuilder
    private var mark: some View {
        switch activity {
        case .running:
            DotRingLoader(
                colour: theme.status.running.color,
                unlit: theme.board.unlit.color
            )
        case .succeeded:
            // Filled rather than outlined: at 22pt against a loader that is
            // twelve small dots, an outlined tick reads as the lighter of the
            // two states, and finishing is the heavier one.
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.status.succeeded.color)
        case let .failed(code):
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.status.failed.color)
                .accessibilityLabel("Exit \(code)")
        case .idle:
            EmptyView()
        }
    }

    private var headline: String {
        switch activity {
        case .idle: "Waiting"
        case .running: "Working"
        // "Done", not "Succeeded". What is actually known is that the agent
        // stopped; whether the work is right is not something the transcript
        // can say, and a word like "Succeeded" claims it.
        case .succeeded: "Done"
        case .failed: "Stopped"
        }
    }

    private var detail: String? {
        switch activity {
        case let .failed(code): "Exit \(code)"
        default: task
        }
    }
}
