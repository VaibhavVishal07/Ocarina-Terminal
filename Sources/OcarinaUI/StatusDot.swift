import OcarinaTerminalContext
import SwiftUI

/// The tab's activity, as a single dot.
///
/// Colour is the whole signal — no glyphs, no labels — so a strip of twenty
/// tabs stays scannable. Idle is lit rather than grey: a tab waiting at a
/// prompt is open and ready, not switched off, and a strip of grey dots was
/// the reason none of them read as meaning anything.
struct StatusDot: View {
    @Environment(\.theme) private var theme
    let activity: TabActivity

    /// Themed, but still semantic: a theme may recolour these and they still
    /// have to mean stop and go, so they are their own token group rather than
    /// borrowing the accent.
    private var color: Color {
        switch activity {
        case .idle: theme.status.idle.color
        case .running: theme.status.running.color
        case .succeeded: theme.status.succeeded.color
        // The accent rather than a fifth colour in `Theme.Status`, which every
        // theme file would have had to grow. It is the colour this app already
        // uses to mean "this is the thing", and a tab asking for you is the
        // thing. See `TabIcon` for the same argument: name the slot, and let
        // the theme say what colour that is.
        case .needsYou: theme.chrome.accent.color
        case .failed: theme.status.failed.color
        }
    }

    private var label: String {
        switch activity {
        case .idle: "Idle"
        case .running: "Working"
        case .succeeded: "Finished"
        case .needsYou: "Needs you"
        case let .failed(code): "Failed (exit \(code))"
        }
    }

    var body: some View {
        dot
            .frame(width: 9, height: 9)
            .help(label)
    }

    @ViewBuilder
    private var dot: some View {
        let circle = Circle().fill(color)
        if activity.isRunning {
            // `.animation(_:value:)` with `repeatForever` never actually ran.
            // The value it watched was set once on appear, so by the time a
            // tab was busy there was no change left to animate and the dot
            // just sat at its dimmed opacity — which is why every tab looked
            // equally dull. A phase animator carries its own clock, so the
            // pulse starts when the work does and stops when it ends.
            circle.phaseAnimator([false, true]) { view, isDim in
                view
                    .opacity(isDim ? 0.45 : 1)
                    .scaleEffect(isDim ? 0.86 : 1)
            } animation: { _ in
                // Slow and shallow. A fast blink in the corner of the eye is
                // an alarm; this only has to say "still going".
                .easeInOut(duration: 0.9)
            }
        } else {
            circle
        }
    }
}
