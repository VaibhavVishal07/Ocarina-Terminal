import OcarinaTerminalContext
import SwiftUI

/// The tab's activity, as a single dot.
///
/// Colour is the whole signal — no glyphs, no labels — so a strip of twenty
/// tabs stays scannable. Idle keeps a dim dot rather than nothing, so titles
/// do not shift sideways as tabs start and finish.
struct StatusDot: View {
    let activity: TabActivity
    @State private var isPulsing = false

    private var color: Color {
        switch activity {
        case .idle: .secondary.opacity(0.35)
        case .running: Color(red: 0.35, green: 0.62, blue: 1.0)
        case .succeeded: Color(red: 0.30, green: 0.78, blue: 0.45)
        case .failed: Color(red: 0.95, green: 0.35, blue: 0.35)
        }
    }

    private var label: String {
        switch activity {
        case .idle: "Idle"
        case .running: "Running"
        case .succeeded: "Finished"
        case let .failed(code): "Failed (exit \(code))"
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(activity.isRunning && isPulsing ? 0.35 : 1)
            .animation(
                activity.isRunning
                    ? .easeInOut(duration: 0.75).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .help(label)
    }
}
