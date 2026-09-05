import OcarinaTerminalContext
import SwiftUI

/// The tab's activity, as a single dot.
///
/// Colour is the whole signal — no glyphs, no labels — so a strip of twenty
/// tabs stays scannable. Idle is lit rather than grey: a tab waiting at a
/// prompt is open and ready, not switched off, and a strip of grey dots was
/// the reason none of them read as meaning anything.
struct StatusDot: View {
    let activity: TabActivity

    private static let idle = Color(red: 0.53, green: 0.78, blue: 1.0)
    private static let running = Color(red: 0.36, green: 0.66, blue: 1.0)
    private static let succeeded = Color(red: 0.30, green: 0.78, blue: 0.45)
    private static let failed = Color(red: 0.95, green: 0.35, blue: 0.35)

    private var color: Color {
        switch activity {
        case .idle: Self.idle
        case .running: Self.running
        case .succeeded: Self.succeeded
        case .failed: Self.failed
        }
    }

    private var label: String {
        switch activity {
        case .idle: "Idle"
        case .running: "Working"
        case .succeeded: "Finished"
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
