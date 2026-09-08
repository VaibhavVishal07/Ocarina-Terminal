import SwiftUI

/// What the terminal looks like while a file is being dragged over it.
///
/// Written for somebody who has never used a terminal. The gesture they know
/// is the web one — drag a file at a page, the page dims, a dashed box appears
/// and tells you what will happen if you let go — so that is what this is. A
/// native app would draw a two-point focus ring and say nothing, which is fine
/// if you already know that a terminal takes files and what it does with them.
/// Nobody arriving at this app knows either.
///
/// The sentence is the important part. Dropping a file here does not upload it
/// or open it: it types the path. Saying so before the mouse is released is the
/// difference between a feature and a surprise.
struct DropZoneView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            // The scrim, so the terminal reads as behind this rather than
            // beside it. Dark on any theme: the box and its text are the only
            // things that should be legible for the moment they are up.
            theme.terminal.background.color.opacity(0.72)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.document")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(theme.chrome.accent.color)

                Text("Drop to add it here")
                    .font(theme.uiFont(15, weight: .semibold))
                    .foregroundStyle(theme.chrome.textPrimary.color)

                Text("The file's location is typed at the prompt.\nNothing is uploaded, and nothing runs.")
                    .font(theme.uiFont(11.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.chrome.textSecondary.color)
            }
            .padding(.horizontal, 26)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    theme.chrome.accent.color.opacity(0.75),
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
                .padding(9)
        }
        .allowsHitTesting(false)
    }
}
