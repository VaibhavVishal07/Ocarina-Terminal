import SwiftUI

/// Shown when something worth explaining is about to be pasted.
struct PasteReviewView: View {
    @Environment(\.theme) private var theme
    let reading: PasteInspector.Reading
    let paste: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reading.isDestructive ? "Read this before you paste it" : "About to paste")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.chrome.textPrimary.color)

            ScrollView {
                Text(reading.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 130)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.terminal.background.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.chrome.border.color.opacity(0.14), lineWidth: 1)
                    }
            }

            if reading.lineCount > 1 {
                label("This is \(reading.lineCount) separate commands, not one.",
                      symbol: "list.number", tint: theme.chrome.textSecondary.color)
            }
            ForEach(reading.concerns) { concern in
                label(concern.note,
                      symbol: concern.isDestructive ? "exclamationmark.triangle.fill" : "info.circle",
                      tint: concern.isDestructive
                          ? theme.status.failed.color
                          : theme.chrome.textSecondary.color)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel)
                    .controlSize(.regular)
                // Still says paste, not run: this puts the text at the prompt
                // and stops. Nothing here presses Return.
                Button("Paste it", action: paste)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(reading.isDestructive
                          ? theme.status.failed.color
                          : theme.chrome.accent.color)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(theme.chrome.panelTop.color)
    }

    private func label(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.chrome.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
