import SwiftUI

/// The strip across the window that says what happened to a skill.
///
/// A quieter object than `ErrorBannerView` beside it, and deliberately. That
/// one interrupts, because a command failing is the moment a new user stops and
/// the one place a single button turns a dead end into a next step. This one
/// reports: a skill went in, or is waiting for an agent, and in neither case is
/// anything wrong. So it is a line of text and a way to dismiss it, in the
/// window's own chrome colours rather than in a status colour — the only one of
/// the three states that is a problem says so in words.
///
/// It exists because the browser is a modal. Everything the app knew about an
/// install used to be drawn inside it — the spinner on the row, the "Installed"
/// label — so closing the browser took all of it away, and the only remaining
/// evidence that anything had happened was a folder appearing in a directory
/// nobody looks at.
struct SkillNoticeView: View {
    @Environment(\.theme) private var theme
    let notice: SkillShelf.Notice
    /// What the named button does. Only drawn when the notice names one.
    let act: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(theme.uiFont(11, weight: .medium))
                .foregroundStyle(theme.chrome.textTertiary.color)

            Text(notice.text)
                .font(theme.uiFont(12))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let action = notice.action {
                Button(action: act) {
                    Text(action)
                        .font(theme.uiFont(11, weight: .semibold))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            Capsule().stroke(
                                theme.chrome.border.color.opacity(0.35), lineWidth: 1
                            )
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(theme.uiFont(9.5, weight: .semibold))
                    .foregroundStyle(theme.chrome.textTertiary.color)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.chrome.panelTop.color.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.chrome.border.color.opacity(0.22), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
    }

    /// One mark, and the only thing on the strip that distinguishes the three.
    private var symbol: String {
        switch notice.kind {
        case .done: "checkmark"
        case .waiting: "clock"
        case .trouble: "exclamationmark.triangle"
        }
    }
}
