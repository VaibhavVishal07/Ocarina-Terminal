import SwiftUI

/// Shown across the top of a terminal whose last command failed.
///
/// A red exit code means nothing to someone who has never seen one, and the
/// output above it is usually worse. This is the one moment where the app
/// should interrupt: it is the point at which a new user stops, and the only
/// point where a single button can turn a dead end into the next step.
struct ErrorBannerView: View {
    @Environment(\.theme) private var theme
    let exitCode: Int
    let hasAgent: Bool
    let explain: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(theme.status.failed.color)
                .frame(width: 7, height: 7)

            // Names the fact without dressing it up. "Exit code 1" is the
            // technical truth and says nothing; this says what happened.
            Text("That didn't work.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)

            Text("The last command stopped with an error (code \(exitCode)).")
                .font(.system(size: 14))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(hasAgent ? "Explain this" : "Get something that can explain it", action: explain)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(theme.chrome.accent.color)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                    .frame(width: 18, height: 18)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(theme.chrome.panelTop.color)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.status.failed.color.opacity(0.5))
                        .frame(height: 1)
                }
        }
    }
}
