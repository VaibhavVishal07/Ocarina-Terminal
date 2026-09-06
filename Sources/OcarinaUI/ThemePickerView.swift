import SwiftUI

/// Picking a theme by looking at its colours.
///
/// An earlier version drew each card as a miniature of the whole window —
/// sidebar rows, fake terminal output, a caret. It was more faithful and worse
/// to use: fourteen tiny screenshots is a lot to read when the question is only
/// "which colour do I want today". A card is now the surface and its palette,
/// which is the thing being chosen.
struct ThemePickerView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: OcarinaModel
    let close: () -> Void

    /// Narrow enough for five across, so fourteen themes are all on screen at
    /// once. Scrolling a picker to find a colour defeats the point of showing
    /// the colours.
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.themes.available) { option in
                        Button {
                            // Applied on the spot. There is nothing to confirm,
                            // because you are looking at the result.
                            model.themes.select(option.id)
                        } label: {
                            ThemeSwatch(
                                theme: option,
                                isSelected: option.id == model.themes.selectedID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 460)

            tinting

            if !model.themes.rejected.isEmpty { rejected }
        }
        .frame(width: 572)
        .background(theme.chrome.panelTop.color)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.chrome.border.color.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.chrome.textPrimary.color)
                Text("Applies as you pick. Click anywhere outside to close.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.chrome.textTertiary.color)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                    .frame(width: 20, height: 20)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 2)
    }

    /// The one thing about a theme that is a choice rather than a colour.
    ///
    /// It sits under the swatches instead of in the sidebar's settings,
    /// because it is not a setting about the app: it is the answer to "how far
    /// does the theme go", and the place you ask that is the place you are
    /// choosing the theme.
    private var tinting: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.14)).frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recolour programs to match")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.chrome.textPrimary.color)
                    Text("A program's own accent — Claude Code's gold — is toned down to plain text, and its blues take the theme's unless that would read as a red or a green. Red, green and grey are left alone. Output already on screen keeps the colours it arrived in.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.chrome.textTertiary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { model.themes.tintsProgramColours },
                    set: { model.setTinting($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(theme.chrome.accent.color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// Themes that loaded and were turned away, with the reason. Listed rather
    /// than dropped: a theme you wrote and cannot find is worse than one shown
    /// as broken.
    private var rejected: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(theme.chrome.border.color.opacity(0.14)).frame(height: 1)
            ForEach(model.themes.rejected, id: \.themeID) { report in
                Text("“\(report.themeID)” is not offered — \(report.unreadable.count) of its colours are unreadable on its own background.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.chrome.textSecondary.color)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 12)
    }
}

/// One theme: its surface, its texture, its sixteen colours.
private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                theme.terminal.background.color
                // The texture belongs here — it is as much the theme as the
                // hue is, and it is the only way to tell Steel from Midnight.
                VStack {
                    Spacer(minLength: 0)
                    swatches
                }
                .padding(6)
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }

            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.10 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(isSelected ? 0.40 : 0.08),
                                lineWidth: isSelected ? 1.5 : 1)
                }
        }
    }

    /// The eight base colours, once. The bright variants sit a shade above
    /// them and told you nothing at this size that the base row did not.
    private var swatches: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(theme.terminal.palette.prefix(8).enumerated()), id: \.offset) { _, colour in
                RoundedRectangle(cornerRadius: 1)
                    .fill(colour.color)
                    .frame(height: 6)
            }
        }
    }
}
