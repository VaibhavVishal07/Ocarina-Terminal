import SwiftUI

/// Shown when every tab has been closed.
struct EmptyStateView: View {
    let onNewTab: () -> Void

    private static let wordmark = """
    ███╗   ███╗ █████╗      ██╗ ██████╗ ██████╗  █████╗ 
    ████╗ ████║██╔══██╗     ██║██╔═══██╗██╔══██╗██╔══██╗
    ██╔████╔██║███████║     ██║██║   ██║██████╔╝███████║
    ██║╚██╔╝██║██╔══██║██   ██║██║   ██║██╔══██╗██╔══██║
    ██║ ╚═╝ ██║██║  ██║╚█████╔╝╚██████╔╝██║  ██║██║  ██║
    ╚═╝     ╚═╝╚═╝  ╚═╝ ╚════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
    """

    var body: some View {
        VStack(spacing: 22) {
            Text(Self.wordmark)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.55))
                .fixedSize()
                .accessibilityLabel("Majora")

            Text("No terminals open.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button(action: onNewTab) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Terminal")
                        .font(.system(size: 13, weight: .medium))
                    Text("⌘T")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.10))
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.white.opacity(0.10))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
